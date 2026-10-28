import AppKit
import MenuBarClientShim

/// HoverRegion · BarMachine · Sections를 실제 메뉴바에 연결한다.
///
/// 배치(왼→오): `[always hidden] ‖ [hidden] | [보이는 아이콘]`
/// 숨김은 macOS 27 비공개 API에 "이 앱들만 보여 줘"라는 허용 목록을 넘겨서 한다(MenuBarClientShim).
/// 폭으로 밀어내지 않으니 화면 크기·개수와 상관없이 똑같이 동작한다.
///
/// `@MainActor`: 이 클래스의 코드는 전부 메인 스레드에서만 돈다. AppKit UI는 메인 스레드 전용이다.
/// `NSObject`를 상속하는 이유: 우클릭 메뉴가 열리고 닫히는 걸 알려 주는 NSMenuDelegate가 Objective-C 프로토콜이라서
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    /// 시스템 아이템 번호. 모르는 번호는 무시되므로 넉넉히 잡는다(dwarvesf/hidden: 27.0에서 0–63 확인)
    private static let systemItemsToKeep: [NSNumber] = (0..<64).map { NSNumber(value: $0) }
    private static let separatorLength: CGFloat = 12

    /// UserDefaults 키. 문자열을 여러 곳에 쓰면 오타 하나가 조용히 설정을 잃게 만든다
    private enum Key {
        static let revealMode = "revealMode"
        static let sections = "sections"
        static let pending = "pending"
    }

    private let hiddenSeparator: NSStatusItem
    private let alwaysSeparator: NSStatusItem
    private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.kimmojae.bulldozer"

    private var machine = BarMachine(mode: RevealMode(rawValue: UserDefaults.standard.string(forKey: Key.revealMode) ?? "") ?? .hover)
    private var screens: [ScreenGeometry] = []
    /// 앱별 구역. 다시 켜도 유지되게, 바뀔 때만 저장한다
    private var store = MenuBarController.loadStore() {
        didSet { if store != oldValue { Self.saveStore(store) } }
    }
    /// 화면 오른쪽 끝에서 가장 왼쪽 상태 아이콘까지의 폭. 접혀 있을 때 이 왼쪽(빈 곳)에서만 호버로 펼친다
    private var statusWidth: CGFloat?

    /// 비공개 API가 준 숨김 유지 객체. 이게 살아 있는 동안만 숨김이 유지된다
    private var assertion: AnyObject?
    /// 늦게 도착한 결과(숨김 활성화, 지연된 적용)가 최신 결정을 덮지 않게 하는 번호
    private var generation = 0

    /// 아이콘 읽기는 앱 수십 개를 도느라 ~1초 걸려서 한 번에 하나만 돌린다. 도는 중에 또 요청되면 끝나고 한 번 더
    private var reading = false
    private var readAgain = false
    /// ⌘-드래그를 놓은 직후의 상태. 그 위치를 읽기 전에 숨김을 바꾸면 옮긴 아이콘 위치가 엉뚱하게 읽혀서,
    /// 읽기가 끝날 때까지 메뉴바를 그대로 둔다
    private var heldForDrop: BarState?
    private var readTicks = 0
    private var appsObservation: NSKeyValueObservation?

    /// 이번 상태에서 «를 이미 다뤘는가. 사용자가 »로 닫은 걸 주기적 읽기가 다시 열지 않게, 상태가 바뀔 때만 다시 본다
    private var overflowHandled = false
    /// 우리가 연 «. 접을 때 이것만 닫는다(사용자가 연 건 건드리지 않는다)
    private var openedOverflow = false
    /// «를 누르려고 보낸 클릭이 globalClick으로 되돌아오는 걸 무시할 시각
    private var ignoreClicksUntil: TimeInterval = 0

    /// 펼친 상태에서 마지막으로 읽은 아이콘 위치. 메뉴바를 클릭했을 때 어느 앱 아이콘인지 찾는 데 쓴다
    private var shownItems: [StatusItemInfo] = []
    /// 펼친 상태에서 누른 아이콘의 앱. 그 앱의 창(팝오버 등)을 클릭하는 건 아직 그 앱을 쓰는 중이라 접지 않는다
    private var clickedApp: String?

    private static let hiddenImage = NSImage(systemSymbolName: "poweron", accessibilityDescription: MenuBarInventory.hiddenSeparatorLabel)
    /// `‖`. SF Symbol에 얇은 이중선이 없어(pause는 재생 버튼처럼 보인다) `poweron`과 비슷한 굵기로 직접 그린다
    private static let alwaysImage: NSImage = {
        let image = NSImage(size: NSSize(width: 7, height: 14), flipped: false) { _ in
            // 칠할 색을 정하지 않으면 아무것도 안 그려진다(실측). 템플릿이라 실제 색은 메뉴바가 정한다
            NSColor.black.setFill()
            for x in [1.0, 4.5] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 1.5, width: 1.5, height: 11), xRadius: 0.75, yRadius: 0.75).fill()
            }
            return true
        }
        // 템플릿 이미지: 색은 무시하고 모양만 써서, 메뉴바가 밝든 어둡든 알맞은 색으로 칠해 준다
        image.isTemplate = true
        image.accessibilityDescription = MenuBarInventory.alwaysSeparatorLabel
        return image
    }()

    override init() {
        // 새 아이템은 메뉴바 맨 왼쪽에 생기므로, H를 먼저 만들어야 AH가 그 왼쪽에 온다.
        // autosaveName을 바꾸면 macOS가 기억한 구분자 위치를 잃는다
        hiddenSeparator = Self.makeSeparator("bulldozer_hidden_v2", image: Self.hiddenImage)
        alwaysSeparator = Self.makeSeparator("bulldozer_always_v2", image: Self.alwaysImage)
        // NSObject를 상속하면 내 프로퍼티를 다 채운 뒤 부모 init을 불러야 self를 쓸 수 있다
        super.init()
        hiddenSeparator.button?.target = self
        hiddenSeparator.button?.action = #selector(hiddenSeparatorClicked)
        hiddenSeparator.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        refreshScreens()
        if !MenuBarInventory.isTrusted { MenuBarInventory.requestTrust() }
        // 시작할 때는 아직 숨김이 없어 전부 펼친 것과 같다. 그 위치를 읽은 다음 접는다
        read(trustAs: .expandedAll) { [weak self] in
            // `[weak self]`: 클로저가 컨트롤러를 붙잡아 두지 않게 한다. 그래서 self가 옵셔널(self?)이 된다
            self?.applyCurrentState()
            self?.startWatching()
        }
    }

    /// accessibilityDescription(이미지에 붙음)이 손쉬운 사용 API에서 AXDescription으로 읽혀,
    /// 아이콘을 읽을 때 우리 구분자를 찾는 표식이 된다
    private static func makeSeparator(_ autosaveName: String, image: NSImage?) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: separatorLength)
        item.autosaveName = autosaveName
        item.button?.image = image
        item.button?.imageScaling = .scaleProportionallyDown
        return item
    }

    // MARK: - 감시

    private func startWatching() {
        // 예약된 타이머는 런루프가 붙잡고 있어서 따로 보관하지 않는다
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            // 타이머는 메인 런루프에서 돌지만, 컴파일러는 그걸 모른다. assumeIsolated로 "메인 스레드 맞다"고 알려 준다
            MainActor.assumeIsolated { self?.tick() }
        }
        // 아이콘은 펼쳐져 있으면 2초마다(놓친 이동), 접혀 있으면 10초마다(시계처럼 폭이 바뀌는 아이콘, 늦게 뜬 새 앱) 다시 읽는다
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.readTicks += 1
                if self.machine.state != .collapsed || self.readTicks % 5 == 0 { self.read() }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshScreens() }
        }

        // 다른 앱에서 난 클릭만 들어온다(우리 앱 클릭은 안 옴). 손쉬운 사용 권한 없이도 동작한다
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.globalClick() }
        }
        // ⌘-드래그로 아이콘을 놓으면, 메뉴바가 다시 그려진 뒤 위치를 읽을 때까지 숨김을 그대로 둔다
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.machine.state != .collapsed, NSEvent.modifierFlags.contains(.command),
                      HoverRegion.inMenuBar(NSEvent.mouseLocation, screens: self.screens) else { return }
                self.heldForDrop = self.machine.state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated { self.read() }
                }
            }
        }

        // 새로 켜진 앱의 아이콘은 hidden으로 넣는다. 아이콘이 생길 시간을 조금 주고 읽는다.
        // didLaunchApplicationNotification은 Dock 아이콘 없는(LSUIElement) 앱에는 안 와서 — 메뉴바 앱 대부분이 그렇다 —
        // 실행 중인 앱 목록 자체를 지켜본다(KVO). 아이콘을 더 늦게 만드는 앱은 주기적 읽기가 잡는다
        appsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, change in
            guard change.kind != .removal else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                MainActor.assumeIsolated { self?.read() }
            }
        }
    }

    private func tick() {
        // 접혀 있을 때는 빈 곳에서만 펼친다(아이콘을 누르러 갈 때 펼쳐지지 않게).
        // 펼친 뒤에는 메뉴바 줄 전체에서 유지한다. 넘친 아이콘(«)이 노치 왼쪽에 펼쳐지기 때문이다
        let point = NSEvent.mouseLocation
        let inBar = machine.state == .collapsed
            ? HoverRegion.contains(point, screens: screens, statusWidth: statusWidth)
            : HoverRegion.inMenuBar(point, screens: screens)
        transition { $0.pointer(inBar: inBar, at: Self.now) }
    }

    private func globalClick() {
        if Self.now < ignoreClicksUntil { return }
        // ⌘를 누른 클릭은 아이콘 옮기기(⌘-드래그)다. 어디에 놓을지 보이게 전부 펼친다.
        // 메뉴를 쓰는 중으로 보고 고정하지는 않는다 — 고정하면 마우스를 내려도 안 접힌다(실측)
        if NSEvent.modifierFlags.contains(.command) {
            if HoverRegion.inMenuBar(NSEvent.mouseLocation, screens: screens) {
                transition { $0.commandDragBegan() }
            }
            return
        }
        // 펼쳐져 있을 때만 의미가 있어서(clickedInBar) 펼친 상태와 같은 영역(메뉴바 줄 전체)으로 본다
        let point = NSEvent.mouseLocation
        if HoverRegion.inMenuBar(point, screens: screens) {
            let at = Self.axPoint(point)
            clickedApp = machine.state == .collapsed ? nil : shownItems.first { $0.frame.contains(at) }?.bundleID
            transition { $0.clickedInBar() }
        } else if let clickedApp, MenuBarInventory.windowOwner(at: Self.axPoint(point)) == clickedApp {
            // 아이콘을 눌러 연 팝오버 안을 클릭함. 접으면 아이콘이 숨으면서 팝오버도 붙어 있던 자리를 잃는다
            return
        } else {
            clickedApp = nil
            let now = Self.now
            transition { $0.clickedOutsideBar(at: now) }
        }
    }

    @objc private func hiddenSeparatorClicked() {
        guard let event = NSApp.currentEvent else { return }
        // macOS 27은 메뉴바 클릭을 MenuBarAgent가 받아 넘겨 주면서 이벤트의 수정키를 잃을 수 있어,
        // 지금 키보드에서 눌린 수정키(NSEvent.modifierFlags)도 같이 본다
        let modifiers = event.modifierFlags.union(NSEvent.modifierFlags)
        if event.type == .rightMouseUp || modifiers.contains(.control) {
            showMenu()
        } else {
            transition { $0.separatorClicked() }
        }
    }

    // MARK: - 우클릭 메뉴

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        for mode in [RevealMode.hover, .click] {
            let item = NSMenuItem(title: mode == .hover ? "Show on Hover" : "Show on Click",
                                  action: #selector(chooseRevealMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = machine.mode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Bulldozer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // 메뉴를 잠깐 붙여 띄운 뒤 다시 뗀다. 붙여 두면 왼쪽 클릭도 메뉴를 열어 버린다(NoahSmo/HiddenBar 방식)
        hiddenSeparator.menu = menu
        hiddenSeparator.button?.performClick(nil)
        hiddenSeparator.menu = nil
    }

    @objc private func chooseRevealMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = RevealMode(rawValue: raw) else { return }
        UserDefaults.standard.set(raw, forKey: Key.revealMode)
        let before = machine.state
        transition { $0.mode = mode }
        // 접힌 상태 그대로여도 클릭 모드는 구분자를 남겨야 하므로 다시 적용한다
        if machine.state == before { applyCurrentState() }
    }

    @objc private func toggleLoginItem() {
        LoginItem.toggle()
    }

    /// 메뉴가 열린 동안 포인터가 메뉴 쪽(메뉴바 아래)으로 내려가도 접히지 않게 고정한다.
    /// 접히면 `|`가 숨겨지면서 메뉴가 붙어 있던 자리가 사라진다
    /// `nonisolated`: 델리게이트 메서드는 프로토콜 쪽에서 스레드를 정하지 않아서, 메인 스레드라고 직접 알려 준다
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated { transition { $0.clickedInBar() } }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            let now = Self.now
            transition { $0.menuClosed(at: now) }
        }
    }

    /// 상태 머신을 한 번 움직이고, 상태가 바뀌었을 때만 적용한다.
    /// `(inout BarMachine) -> Void`: 받은 machine을 직접 고치는 클로저. `$0`이 그 machine이다
    private func transition(_ change: (inout BarMachine) -> Void) {
        let before = machine.state
        change(&machine)
        guard machine.state != before else { return }
        overflowHandled = false
        applyCurrentState()
        // 메뉴바가 다시 그려진 뒤 한 번 읽는다. 펼쳤으면 위치·새 앱을, 접었으면 빈 곳 폭을 얻는다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.read() }
        }
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// AppKit 좌표(주 화면 왼쪽 아래 기준, y가 위로) → 손쉬운 사용·CGWindow 좌표(주 화면 왼쪽 위 기준, y가 아래로)
    private static func axPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
    }

    // MARK: - 아이콘 읽기

    /// 아이콘 읽기 하나로 세 가지를 얻는다: 새 앱, 위치(펼쳐져 있을 때), 빈 곳 폭(접혀 있을 때).
    /// - trustAs: 어느 상태에서 본 위치로 믿을지. 기본은 지금 상태, ⌘-드래그 직후면 놓을 때의 상태
    private func read(trustAs override: BarState? = nil, then done: (@MainActor () -> Void)? = nil) {
        guard MenuBarInventory.isTrusted else {
            // 권한이 없으면 읽을 수 없으니 붙잡아 둔 것도 놓는다
            if heldForDrop != nil { heldForDrop = nil; applyCurrentState() }
            done?()
            return
        }
        guard !reading else { readAgain = true; return }
        reading = true
        let state = override ?? heldForDrop ?? machine.state
        let releasesHold = heldForDrop != nil
        MenuBarInventory.snapshot(screens: screens) { [weak self] snapshot in
            guard let self else { return }
            self.reading = false
            let before = self.store
            self.store.addDiscovered(snapshot.owners, ownBundleID: self.ownBundleID)
            if state == .collapsed {
                self.statusWidth = self.statusWidth(of: snapshot.items) ?? self.statusWidth
            } else if let hiddenX = snapshot.hiddenSeparatorX {
                self.shownItems = snapshot.items
                let positions = Sections.resolve(items: snapshot.items, hiddenSeparatorX: hiddenX,
                                                 alwaysSeparatorX: snapshot.alwaysSeparatorX, ownBundleID: self.ownBundleID)
                self.store.merge(positions: positions, takenWhile: state, alwaysSeparatorKnown: snapshot.alwaysSeparatorX != nil)
            }
            if releasesHold {
                self.heldForDrop = nil
                self.applyCurrentState()
            } else if self.store != before {
                self.applyRestriction()
            } else if state == self.machine.state {
                // 읽는 동안 상태가 바뀌었거나 숨김을 다시 거는 중이면 위치가 안 맞아 다음 읽기에 맡긴다
                self.followOverflow(snapshot)
            }
            done?()
            if self.readAgain {
                self.readAgain = false
                self.read()
            }
        }
    }

    // MARK: - 넘침 («)

    /// 펼친 동안은 넘친 아이콘도 노치 왼쪽에 이어서 보이게 «를 대신 누르고, 접히면 우리가 연 것만 닫는다
    private func followOverflow(_ snapshot: MenuBarInventory.Snapshot) {
        // 누르고 있는 중(⌘-드래그 등)에 클릭을 보내면 그 동작이 끊긴다. 다음 읽기에서 다시 본다
        guard !overflowHandled, NSEvent.pressedMouseButtons == 0, heldForDrop == nil else { return }
        let allowed = Sections.allowed(for: machine.state, sections: store.sections, ownBundleID: ownBundleID,
                                       keepSeparator: machine.mode == .click).map(Set.init)
        let shown = snapshot.items.filter { Sections.systemOwners.contains($0.bundleID) || allowed?.contains($0.bundleID) ?? true }
        overflowHandled = true
        guard let button = snapshot.overflowButton else {
            openedOverflow = false
            return
        }
        let isOpen = Overflow.isOpen(button: button, shown: shown)
        if machine.state != .collapsed, !isOpen {
            press(button)
            openedOverflow = true
        } else if machine.state == .collapsed, isOpen, openedOverflow {
            press(button)
            openedOverflow = false
        }
    }

    /// «는 손쉬운 사용으로 누를 수 없고(AXPress 미지원), MenuBarAgent에 직접 보낸 클릭에도 반응하지 않아 실제 클릭을 보낸다(실측).
    /// 클릭하면 커서가 그 자리로 옮겨지므로 바로 제자리로 돌려놓는다
    private func press(_ frame: CGRect) {
        guard let back = CGEvent(source: nil)?.location else { return }
        // 손쉬운 사용 좌표와 CGEvent 좌표는 기준(주 화면 왼쪽 위)이 같다
        let point = CGPoint(x: frame.midX, y: frame.midY)
        ignoreClicksUntil = Self.now + 0.3
        Self.post(.leftMouseDown, at: point)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Self.post(.leftMouseUp, at: point)
            CGWarpMouseCursorPosition(back)
            // 커서를 옮기면 잠깐 마우스 움직임이 막힌다. 바로 다시 잇는다
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    private nonisolated static func post(_ type: CGEventType, at point: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .privateState), mouseType: type,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cgSessionEventTap)
    }

    /// 접힌 상태에서 보이는 아이콘(보이는 구역 앱 + 시스템)의 왼쪽 끝을 잰다.
    /// 숨은 아이콘은 엉뚱한 위치를 주므로 뺀다. 손쉬운 사용 좌표는 왼쪽 위 기준(y가 아래로)이라 화면도 그 기준으로 바꿔 찾는다
    private func statusWidth(of items: [StatusItemInfo]) -> CGFloat? {
        let shown = items.filter { Sections.systemOwners.contains($0.bundleID) || store.sections[$0.bundleID] == .visible }
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let leftmost = shown.min(by: { $0.frame.minX < $1.frame.minX })?.frame else { return nil }
        let screen = NSScreen.screens.first { screen in
            let f = screen.frame
            let topLeft = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
            return topLeft.contains(CGPoint(x: leftmost.midX, y: leftmost.midY))
        }
        return screen.map { $0.frame.maxX - leftmost.minX }
    }

    private static func loadStore() -> SectionStore {
        let defaults = UserDefaults.standard
        let raw = defaults.dictionary(forKey: Key.sections) as? [String: Int] ?? [:]
        var sections = raw.compactMapValues(MenuBarSection.init(rawValue:))
        // 예전에는 새 앱을 옮기기 전까지 hidden으로 두고 `pending`에 올렸다. 그 앱들은 아직 맨 왼쪽에 있으니 always hidden이다
        for bundle in defaults.stringArray(forKey: Key.pending) ?? [] where sections[bundle] != nil {
            sections[bundle] = .alwaysHidden
        }
        let store = SectionStore(sections: sections)
        if defaults.object(forKey: Key.pending) != nil {
            saveStore(store)
            defaults.removeObject(forKey: Key.pending)
        }
        return store
    }

    private static func saveStore(_ store: SectionStore) {
        UserDefaults.standard.set(store.sections.mapValues(\.rawValue), forKey: Key.sections)
    }

    // MARK: - 적용

    private func applyCurrentState() {
        // ⌘-드래그 직후 위치를 읽는 중이면 그대로 둔다. 읽기가 끝나면 다시 부른다
        guard heldForDrop == nil else { return }
        // AH 구분선은 ⌘-드래그로 always hidden 구역을 정할 때(전부 펼침)만 필요하다.
        // isVisible = false는 위치를 잊게 만들어서 폭 0으로 감추고, 그림도 뺀다(폭 0이어도 작은 점으로 보인다)
        let showAlways = machine.state == .expandedAll
        let appearing = showAlways && alwaysSeparator.length == 0
        if (alwaysSeparator.length > 0) != showAlways {
            alwaysSeparator.length = showAlways ? Self.separatorLength : 0
            alwaysSeparator.button?.image = showAlways ? Self.alwaysImage : nil
        }
        guard appearing else { return applyRestriction() }
        // 전부 펼칠 때 `‖`와 always hidden 아이콘이 같이 움직이면 어긋나 보인다. `‖`가 먼저 자리 잡은 뒤 아이콘을 꺼낸다
        generation += 1
        let decided = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, decided == self.generation else { return }
                self.applyRestriction()
            }
        }
    }

    private func applyRestriction() {
        guard MenuBarInventory.isTrusted,
              let allowed = Sections.allowed(for: machine.state, sections: store.sections, ownBundleID: ownBundleID,
                                             keepSeparator: machine.mode == .click)
        else { return releaseAssertion() }
        activate(allowing: allowed)
    }

    /// 새 제한을 먼저 걸고 나서 옛 것을 푼다. 순서를 바꾸면 전환할 때마다 아이콘이 한꺼번에 번쩍인다
    private func activate(allowing bundleIDs: [String]) {
        generation += 1
        let requested = generation
        BDZMenuBarClientActivate(Self.systemItemsToKeep, bundleIDs) { [weak self] newAssertion, error in
            MainActor.assumeIsolated {
                guard let self, requested == self.generation else {
                    if let newAssertion { BDZMenuBarClientInvalidate(newAssertion) }
                    return
                }
                guard let newAssertion else {
                    // 실패하면 숨기지 않는다. 아이콘이 숨은 채 남는 것보다 낫다
                    NSLog("Bulldozer: 숨김 실패 \(error?.localizedDescription ?? "")")
                    return self.releaseAssertion()
                }
                let old = self.assertion
                self.assertion = newAssertion as AnyObject
                if let old { BDZMenuBarClientInvalidate(old) }
            }
        }
    }

    private func releaseAssertion() {
        generation += 1
        if let assertion { BDZMenuBarClientInvalidate(assertion) }
        assertion = nil
    }

    private func refreshScreens() {
        screens = NSScreen.screens.map { screen in
            let top = screen.safeAreaInsets.top
            let height = top > 0 ? top : max(screen.frame.maxY - screen.visibleFrame.maxY, 26)
            return ScreenGeometry(frame: screen.frame, notchRight: screen.auxiliaryTopRightArea, menuBarHeight: height)
        }
    }
}
