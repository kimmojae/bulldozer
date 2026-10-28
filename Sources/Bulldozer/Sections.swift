// Based on Hidden Bar (https://github.com/dwarvesf/hidden), MenuBarLayout.swift (Sections.resolve).
// Copyright (c) 2019 Dwarves Foundation. MIT License.

import CoreGraphics

/// 메뉴바가 지금 어디까지 펼쳐져 있는가.
/// `enum`의 각 `case`는 서로 배타적인 상태 하나다. 셋 중 정확히 하나만 될 수 있다.
enum BarState: Equatable {
    case collapsed    // 보이는 아이콘만
    case expanded     // hidden까지
    case expandedAll  // always hidden까지
}

/// 아이콘이 사용자가 ⌘-드래그로 놓은 구역.
///     [always hidden] AH| [hidden] H| [visible]
enum MenuBarSection: Int, Comparable {
    case visible, hidden, alwaysHidden

    static func < (lhs: MenuBarSection, rhs: MenuBarSection) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 다른 앱의 메뉴바 아이콘 하나. macOS 27의 손쉬운 사용 API가 주는 건 소유 앱과 위치뿐이다.
struct StatusItemInfo: Equatable {
    var bundleID: String
    var frame: CGRect
}

/// 아이콘 위치 → 앱별 구역 → macOS에 넘길 허용 목록.
/// 숨김은 비공개 API(MenuBarClientCore)가 "허용 목록에 없는 앱의 아이콘을 숨긴다"는 방식이라 앱 단위다.
enum Sections {
    /// macOS 자체 아이템(시계, Wi-Fi, 제어 센터…). 앱 단위로 숨길 수 없어 따로 항상 보이게 둔다
    static let systemOwners: Set<String> = ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"]

    static func resolve(items: [StatusItemInfo], hiddenSeparatorX: CGFloat, alwaysSeparatorX: CGFloat?,
                        ownBundleID: String) -> [String: MenuBarSection] {
        var sections: [String: MenuBarSection] = [:]
        for item in items where item.bundleID != ownBundleID && !systemOwners.contains(item.bundleID) {
            let x = item.frame.midX
            let section: MenuBarSection
            if x > hiddenSeparatorX {
                section = .visible
            } else if let always = alwaysSeparatorX, x < always {
                section = .alwaysHidden
            } else {
                section = .hidden
            }
            // 한 앱이 아이콘 여러 개를 가질 수 있는데 숨김은 앱 단위다. 가장 잘 보이는 구역을 따라야
            // 사용자가 보이게 둔 아이콘이 형제 아이콘 때문에 숨지 않는다
            sections[item.bundleID] = min(sections[item.bundleID] ?? section, section)
        }
        return sections
    }

    /// `nil`이면 제한을 아예 풀어 전부 보이게 한다.
    /// 접힘에서 Bulldozer 자신도 빼면 우리 구분자까지 macOS가 치워 줘서 빈칸이 남지 않는다
    /// - keepSeparator: 클릭 모드. 접혀 있어도 클릭할 구분자(Bulldozer 자신)를 남긴다
    static func allowed(for state: BarState, sections: [String: MenuBarSection], ownBundleID: String,
                        keepSeparator: Bool = false) -> [String]? {
        // 못 읽었는데 빈 목록을 넘기면 모든 앱 아이콘이 숨는다. 잘못 숨기느니 안 숨긴다
        guard !sections.isEmpty else { return nil }
        switch state {
        case .collapsed:
            return ((keepSeparator ? [ownBundleID] : []) + bundles(in: [.visible], sections)).sorted()
        case .expanded:
            return ([ownBundleID] + bundles(in: [.visible, .hidden], sections)).sorted()
        case .expandedAll:
            return nil
        }
    }

    private static func bundles(in wanted: Set<MenuBarSection>, _ sections: [String: MenuBarSection]) -> [String] {
        sections.filter { wanted.contains($0.value) }.map(\.key)
    }
}

/// 앱별 구역 저장소. 보이는 위치가 기준이다. 어느 상태에서 읽은 위치를 얼마나 믿을지는 merge(takenWhile:)가 정한다.
/// 새 앱도 예외 없이 위치를 따른다: macOS가 새 아이콘을 맨 왼쪽(`‖` 왼쪽)에 놓으므로 always hidden으로 시작하고,
/// `|`를 눌러 전부 펼친 뒤 옮긴다. 예외를 두면 hover 때 `‖` 양쪽에 아이콘이 섞여 보여 구역을 알아볼 수 없었다(실제로 겪음)
struct SectionStore: Equatable {
    var sections: [String: MenuBarSection] = [:]

    /// - alwaysSeparatorKnown: AH 구분선 위치를 읽었는가. 못 읽으면(노치에서 «« 로 넘침 등) resolve가 H 왼쪽을
    ///   전부 hidden으로 주므로, 그걸 믿고 always hidden 앱을 hidden으로 내리면 always hidden 구역이 비어 버린다
    mutating func merge(positions: [String: MenuBarSection], alwaysSeparatorKnown: Bool = true) {
        // 저장된 게 없으면(처음 실행) 사용자가 이미 해 둔 배치를 그대로 받는다
        guard !sections.isEmpty else {
            sections = positions
            return
        }
        for (bundle, section) in positions {
            if !alwaysSeparatorKnown, sections[bundle] == .alwaysHidden, section == .hidden { continue }
            sections[bundle] = section
        }
    }

    /// 어느 상태에서 읽은 위치인지에 따라 믿을 수 있는 범위가 다르다.
    /// - 전부 펼침: 숨김이 없어 전부 믿는다.
    /// - 펼침(호버): always hidden 앱은 숨어 있어 위치가 엉뚱하고, AH 구분선도 감춰져 있다.
    ///   그래서 always hidden 앱은 건드리지 않고, hidden 앱을 always hidden으로 올리지도 않는다
    mutating func merge(positions: [String: MenuBarSection], takenWhile state: BarState, alwaysSeparatorKnown: Bool = true) {
        guard state == .expanded else {
            return merge(positions: positions, alwaysSeparatorKnown: alwaysSeparatorKnown)
        }
        var trusted: [String: MenuBarSection] = [:]
        for (bundle, section) in positions where sections[bundle] != .alwaysHidden {
            trusted[bundle] = section == .alwaysHidden ? .hidden : section
        }
        merge(positions: trusted, alwaysSeparatorKnown: false)
    }

    /// 실행 중에 새로 켜진 앱. 위치는 숨김 중이라 믿을 수 없고, 메뉴바 아이콘이 있다는 것만 안다.
    /// macOS는 새 아이콘을 맨 왼쪽에 놓으니 always hidden이다
    mutating func addDiscovered(_ bundles: [String], ownBundleID: String) {
        for bundle in bundles where bundle != ownBundleID && !Sections.systemOwners.contains(bundle) && sections[bundle] == nil {
            sections[bundle] = .alwaysHidden
        }
    }
}
