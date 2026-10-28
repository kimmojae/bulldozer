import CoreGraphics
import Testing
@testable import Bulldozer

// 배치(왼→오): [always hidden] AH| [hidden] H| [visible]  — AH는 x=100, H는 x=300
private func item(_ bundle: String, _ x: CGFloat) -> StatusItemInfo {
    StatusItemInfo(bundleID: bundle, frame: CGRect(x: x, y: 0, width: 20, height: 24))
}

@Suite("Sections")
struct SectionsTests {
    private let own = "com.kimmojae.bulldozer"

    @Test("구분자 기준으로 세 구역을 나눈다")
    func threeSections() {
        let s = Sections.resolve(items: [item("a", 50), item("h", 200), item("v", 400)],
                                 hiddenSeparatorX: 300, alwaysSeparatorX: 100, ownBundleID: own)
        #expect(s == ["a": .alwaysHidden, "h": .hidden, "v": .visible])
    }

    @Test("아이콘이 여러 개인 앱은 가장 잘 보이는 구역을 따른다 — 보이게 둔 아이콘이 숨지 않게")
    func mostVisibleWins() {
        let s = Sections.resolve(items: [item("k", 200), item("k", 400)],
                                 hiddenSeparatorX: 300, alwaysSeparatorX: 100, ownBundleID: own)
        #expect(s == ["k": .visible])
    }

    @Test("시스템 아이템과 Bulldozer 자신은 구역에 넣지 않는다")
    func skipsSystemAndSelf() {
        let s = Sections.resolve(items: [item("com.apple.MenuBarAgent", 50), item("com.apple.controlcenter", 50),
                                         item("com.apple.systemuiserver", 50), item(own, 50)],
                                 hiddenSeparatorX: 300, alwaysSeparatorX: 100, ownBundleID: own)
        #expect(s.isEmpty)
    }

    @Test("AH 구분자를 못 읽으면 always hidden 없이 둘로 나눈다")
    func noAlwaysSeparator() {
        let s = Sections.resolve(items: [item("a", 50), item("v", 400)],
                                 hiddenSeparatorX: 300, alwaysSeparatorX: nil, ownBundleID: own)
        #expect(s == ["a": .hidden, "v": .visible])
    }

    @Test("허용 목록: 접힘은 보이는 앱만, 펼침은 hidden과 자신까지, 전부 펼침은 제한 없음")
    func allowList() {
        let s: [String: MenuBarSection] = ["a": .alwaysHidden, "h": .hidden, "v": .visible, "w": .visible]
        #expect(Sections.allowed(for: .collapsed, sections: s, ownBundleID: own) == ["v", "w"])
        #expect(Sections.allowed(for: .expanded, sections: s, ownBundleID: own) == [own, "h", "v", "w"])
        #expect(Sections.allowed(for: .expandedAll, sections: s, ownBundleID: own) == nil)
    }

    @Test("구역을 하나도 못 읽었으면 제한하지 않는다 — 빈 허용 목록은 모든 앱 아이콘을 숨긴다")
    func emptySectionsFailOpen() {
        #expect(Sections.allowed(for: .collapsed, sections: [:], ownBundleID: own) == nil)
        #expect(Sections.allowed(for: .expanded, sections: [:], ownBundleID: own) == nil)
    }

    // MARK: - 저장된 구역 갱신

    @Test("처음 실행이면(저장된 게 없음) 위치를 그대로 따른다 — 이미 always hidden에 둔 아이콘을 지킨다")
    func firstRunTakesPositions() {
        var store = SectionStore()
        store.merge(positions: ["a": .alwaysHidden, "h": .hidden, "v": .visible])
        #expect(store.sections == ["a": .alwaysHidden, "h": .hidden, "v": .visible])
    }

    @Test("아는 앱은 지금 위치를 따른다 — 저장값과 보이는 위치가 어긋나지 않게(실제로 겪음)")
    func knownAppFollowsPosition() {
        var store = SectionStore(sections: ["sun": .alwaysHidden, "v": .visible])
        store.merge(positions: ["sun": .hidden, "v": .visible])
        #expect(store.sections == ["sun": .hidden, "v": .visible])
    }

    @Test("처음 보는 앱도 위치를 따른다 — 새 아이콘은 맨 왼쪽(‖ 왼쪽)에 생기니 always hidden")
    func newAppFollowsPosition() {
        var store = SectionStore(sections: ["v": .visible])
        store.merge(positions: ["v": .visible, "new": .alwaysHidden])
        #expect(store.sections == ["v": .visible, "new": .alwaysHidden])
    }

    @Test("새 앱을 옮기면 그 위치를 따른다")
    func newAppMovedFollowsPosition() {
        var store = SectionStore(sections: ["new": .alwaysHidden])
        store.merge(positions: ["new": .hidden], takenWhile: .expandedAll)
        #expect(store.sections == ["new": .hidden])
    }

    @Test("새 앱은 hover로 펼쳐도 안 보인다 — hidden만 보이고, always hidden은 | 를 눌러야 보인다")
    func newAppNotShownOnHover() {
        var store = SectionStore(sections: ["h": .hidden, "v": .visible])
        store.addDiscovered(["new"], ownBundleID: own)
        #expect(Sections.allowed(for: .expanded, sections: store.sections, ownBundleID: own) == [own, "h", "v"])
        #expect(Sections.allowed(for: .expandedAll, sections: store.sections, ownBundleID: own) == nil)
    }

    @Test("종료한 앱의 구역은 지우지 않는다 — 다시 켜면 그대로")
    func keepsQuitApps() {
        var store = SectionStore(sections: ["gone": .hidden, "v": .visible])
        store.merge(positions: ["v": .visible])
        #expect(store.sections["gone"] == .hidden)
    }

    @Test("실행 중에 발견한 새 앱은 always hidden, 아는 앱·시스템·자신은 그대로")
    func discovered() {
        var store = SectionStore(sections: ["v": .visible])
        store.addDiscovered(["v", "new", own, "com.apple.controlcenter"], ownBundleID: own)
        #expect(store.sections == ["v": .visible, "new": .alwaysHidden])
    }

    @Test("클릭 모드의 접힘은 구분자(자신)를 남긴다 — 클릭할 대상이 있어야 한다")
    func collapsedKeepsSelfInClickMode() {
        let s: [String: MenuBarSection] = ["h": .hidden, "v": .visible]
        #expect(Sections.allowed(for: .collapsed, sections: s, ownBundleID: own, keepSeparator: true) == [own, "v"])
        #expect(Sections.allowed(for: .collapsed, sections: s, ownBundleID: own, keepSeparator: false) == ["v"])
    }

    @Test("AH 구분선을 못 읽었으면(노치에서 «« 로 넘침 등) always hidden 앱을 hidden으로 내리지 않는다")
    func missingAlwaysSeparatorKeepsAlwaysHidden() {
        var store = SectionStore(sections: ["a": .alwaysHidden, "h": .hidden, "v": .visible])
        // AH를 못 읽으면 resolve는 H 왼쪽을 전부 hidden으로 준다
        store.merge(positions: ["a": .hidden, "h": .hidden, "v": .visible], alwaysSeparatorKnown: false)
        #expect(store.sections == ["a": .alwaysHidden, "h": .hidden, "v": .visible])
    }

    @Test("AH 구분선을 못 읽어도 보이는 쪽으로 옮긴 건 반영한다")
    func missingAlwaysSeparatorStillFollowsVisible() {
        var store = SectionStore(sections: ["a": .alwaysHidden])
        store.merge(positions: ["a": .visible], alwaysSeparatorKnown: false)
        #expect(store.sections == ["a": .visible])
    }

    // MARK: - 호버로 펼친 상태(펼침)에서 읽은 위치

    @Test("펼침에서 hidden 자리로 옮긴 앱은 hidden이 된다(실제로 겪음: ⚡3을 옮겼는데 반영 안 됨)")
    func expandedMoveToHidden() {
        var store = SectionStore(sections: ["bolt": .visible, "v": .visible])
        store.merge(positions: ["bolt": .hidden, "v": .visible], takenWhile: .expanded)
        #expect(store.sections == ["bolt": .hidden, "v": .visible])
    }

    @Test("펼침에서는 always hidden 앱 위치를 믿지 않는다 — 숨어 있어 위치가 엉뚱하다")
    func expandedIgnoresAlwaysHiddenApps() {
        var store = SectionStore(sections: ["a": .alwaysHidden, "v": .visible])
        store.merge(positions: ["a": .visible, "v": .visible], takenWhile: .expanded)
        #expect(store.sections["a"] == .alwaysHidden)
    }

    @Test("펼침에서는 AH 구분선이 없으니 hidden 앱을 always hidden으로 바꾸지 않는다")
    func expandedNeverPromotesToAlwaysHidden() {
        var store = SectionStore(sections: ["h": .hidden])
        store.merge(positions: ["h": .alwaysHidden], takenWhile: .expanded)
        #expect(store.sections["h"] == .hidden)
    }

    @Test("전부 펼침에서 읽은 위치는 전부 믿는다")
    func expandedAllTrustsAll() {
        var store = SectionStore(sections: ["a": .alwaysHidden, "h": .hidden])
        store.merge(positions: ["a": .visible, "h": .alwaysHidden], takenWhile: .expandedAll)
        #expect(store.sections == ["a": .visible, "h": .alwaysHidden])
    }
}
