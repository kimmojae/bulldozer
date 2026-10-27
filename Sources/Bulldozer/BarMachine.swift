import Foundation

/// 숨긴 아이콘을 꺼내는 방법. 사용자가 우클릭 메뉴에서 고른다
enum RevealMode: String {
    case hover  // 메뉴바에 머무르면 펼치고, 벗어나면 접는다
    case click  // 구분자를 클릭해서 펼치고 접는다. 접혀 있어도 구분자가 보인다
}

/// 호버·클릭 → 상태 전이. 시간은 밖에서 넣어 준다(테스트에서 숫자로 바로 넣으려고).
///
/// `struct`는 값 타입이라, 자기 값을 바꾸는 메서드에는 `mutating`을 붙여야 한다.
struct BarMachine {
    static let expandDelay: TimeInterval = 0.1
    static let collapseDelay: TimeInterval = 0.5

    /// `private(set)`: 밖에서 읽을 수는 있지만 바꾸는 건 이 타입 안에서만
    private(set) var state: BarState = .collapsed

    /// 모드를 바꾸면 접힌 상태에서 새로 시작한다
    var mode: RevealMode {
        didSet { if mode != oldValue { collapse() } }
    }

    init(mode: RevealMode = .hover) {
        self.mode = mode
    }

    private var enteredAt: TimeInterval?  // 접힌 상태에서 영역에 들어온 시각
    private var leftAt: TimeInterval?     // 펼친 상태에서 영역을 벗어난 시각
    /// 펼친 상태에서 메뉴바를 클릭함 = 숨겼던 아이콘의 메뉴를 쓰는 중일 수 있다. 밖을 클릭할 때까지 접지 않는다
    private var pinned = false

    mutating func pointer(inBar: Bool, at now: TimeInterval) {
        guard mode == .hover else { return }
        if inBar {
            leftAt = nil
            guard state == .collapsed else { return }
            let since = enteredAt ?? now
            enteredAt = since
            if now - since >= Self.expandDelay {
                state = .expanded
                enteredAt = nil
            }
        } else {
            enteredAt = nil
            guard state != .collapsed, !pinned else { return }
            let since = leftAt ?? now
            leftAt = since
            if now - since >= Self.collapseDelay {
                collapse()
            }
        }
    }

    mutating func clickedInBar() {
        guard state != .collapsed else { return }
        pinned = true
        leftAt = nil
    }

    mutating func clickedOutsideBar(at now: TimeInterval) {
        if mode == .click {
            // 클릭 모드는 포인터 위치로 접지 않으니, 밖을 클릭하면 바로 접는다
            if state != .collapsed { collapse() }
            return
        }
        unpin(at: now)
    }

    /// 우클릭 메뉴가 닫힘. 밖 클릭과 달리 고정만 푼다(클릭 모드에서 접지 않는다)
    mutating func menuClosed(at now: TimeInterval) {
        unpin(at: now)
    }

    /// 구분자 클릭 = 한 단계 더 펼치기. 사용자에게는 두 모드가 같은 규칙으로 보인다
    /// (호버 모드의 접힘에서는 구분자가 숨어 있어 누를 수 없고, 펼치는 첫 단계는 호버가 맡는다).
    /// 끝(전부 펼침)에서 누르면 호버 모드는 펼침으로, 클릭 모드는 접힘으로 돌아간다.
    /// ⌥클릭은 macOS 27 MenuBarAgent가 가로채 앱에 오지 않아서 쓰지 않는다(실측)
    mutating func separatorClicked() {
        switch (mode, state) {
        case (.hover, .collapsed): break
        case (_, .collapsed): state = .expanded
        case (_, .expanded): state = .expandedAll
        case (.hover, .expandedAll): state = .expanded
        case (.click, .expandedAll): collapse()
        }
    }

    /// 고정을 풀고, 지금부터 영역 밖 시간을 잰다
    private mutating func unpin(at now: TimeInterval) {
        guard pinned else { return }
        pinned = false
        leftAt = now
    }

    private mutating func collapse() {
        state = .collapsed
        pinned = false
        leftAt = nil
    }
}
