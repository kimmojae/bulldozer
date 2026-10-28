// Based on Hidden Bar (https://github.com/dwarvesf/hidden), AccessibilityMenuBarInventory.swift.
// Copyright (c) 2019 Dwarves Foundation. MIT License.

import AppKit
import ApplicationServices

/// 손쉬운 사용 API로 메뉴바 아이콘(소유 앱 + 위치)을 읽는다.
/// 앱마다 `AXExtrasMenuBar`의 자식이 그 앱의 메뉴바 아이콘이다.
/// 숨김이 걸려 있는 동안 숨은 아이콘은 엉뚱한 위치를 준다. 어떤 위치를 믿을지는 부르는 쪽이 정한다.
enum MenuBarInventory {
    /// 우리 구분자를 다른 아이콘과 같은 좌표계에서 찾으려고 붙이는 이름(AXDescription으로 읽힌다)
    static let hiddenSeparatorLabel = "Bulldozer 숨김 구분자"
    static let alwaysSeparatorLabel = "Bulldozer 항상 숨김 구분자"

    struct Snapshot {
        /// 메뉴바 아이콘이 있는 앱 전부. 안 그려진 아이콘의 앱도 넣는다 — 숨김이 걸린 동안 켠 앱은
        /// 허용 목록에 들기 전까지 안 그려져서, 그려진 것만 보면 영영 발견하지 못한다
        var owners: [String]
        /// 메뉴바 줄 위에 그려진 아이콘만. 위치로 구역을 정할 때 쓴다
        var items: [StatusItemInfo]
        var hiddenSeparatorX: CGFloat?
        var alwaysSeparatorX: CGFloat?
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 시스템 권한 요청 창을 띄운다
    static func requestTrust() {
        // kAXTrustedCheckOptionPrompt의 값. Swift 6은 C 전역 변수를 동시성 안전하지 않다고 막아서 문자열로 쓴다
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 앱 수십 개를 돌며 묻느라 1초쯤 걸려서 메인 스레드 밖에서 돈다. completion은 메인 큐에서 부른다
    /// - screens: 위치는 메뉴바 줄 위에 있는 아이콘 것만 담는다. 넘쳐서(«) 안 그려진 아이콘은 위치가 엉뚱하다
    static func snapshot(screens: [ScreenGeometry], completion: @escaping @MainActor @Sendable (Snapshot) -> Void) {
        // 메뉴바 아이콘은 .app만 가진다. 헬퍼 프로세스까지 물으면 타임아웃을 기다리느라 훨씬 느려진다
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.bundleURL?.pathExtension == "app" }
            .compactMap { app in app.bundleIdentifier.map { (pid: app.processIdentifier, bundleID: $0) } }
        DispatchQueue.global(qos: .userInitiated).async {
            var snapshot = Snapshot(owners: [], items: [], hiddenSeparatorX: nil, alwaysSeparatorX: nil)
            for app in apps {
                let items = statusItems(pid: app.pid)
                if !items.isEmpty { snapshot.owners.append(app.bundleID) }
                for (frame, label) in items where HoverRegion.isOnMenuBar(axFrame: frame, screens: screens) {
                    switch label {
                    case hiddenSeparatorLabel: snapshot.hiddenSeparatorX = frame.midX
                    case alwaysSeparatorLabel: snapshot.alwaysSeparatorX = frame.midX
                    default: snapshot.items.append(StatusItemInfo(bundleID: app.bundleID, frame: frame))
                    }
                }
            }
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    private static func statusItems(pid: pid_t) -> [(CGRect, String?)] {
        let app = AXUIElementCreateApplication(pid)
        // 기본 타임아웃은 앱마다 몇 초라, 바쁜 앱 하나가 전체를 붙잡는다
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let bar = attribute(app, "AXExtrasMenuBar"),
              let children = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
        else { return [] }
        return children.compactMap { child in
            guard let position = attribute(child, kAXPositionAttribute),
                  let size = attribute(child, kAXSizeAttribute) else { return nil }
            var origin = CGPoint.zero
            var extent = CGSize.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &origin)
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
            return (CGRect(origin: origin, size: extent), attribute(child, kAXDescriptionAttribute) as? String)
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
