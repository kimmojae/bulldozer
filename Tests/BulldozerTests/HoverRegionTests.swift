import CoreGraphics
import Testing
@testable import Bulldozer

// 사용자 환경 실측값: 외장 모니터가 내장 위에 있다
private let builtin = ScreenGeometry(
    frame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
    notchRight: CGRect(x: 1064, y: 1205.5, width: 856, height: 37.5),
    menuBarHeight: 37.5)
private let external = ScreenGeometry(
    frame: CGRect(x: 0, y: 1243, width: 1920, height: 1080),
    notchRight: nil,
    menuBarHeight: 26)

// 실측: 외장이 주 화면(원점)이고 내장은 그 아래. auxiliaryTopRightArea는 전역 좌표로 온다
private let externalPrimary = ScreenGeometry(
    frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
    notchRight: nil,
    menuBarHeight: 30)
private let builtinBelow = ScreenGeometry(
    frame: CGRect(x: 0, y: -1243, width: 1920, height: 1243),
    notchRight: CGRect(x: 1064, y: -37.5, width: 856, height: 37.5),
    menuBarHeight: 37.5)
private let externalFirst = [externalPrimary, builtinBelow]

@Suite("HoverRegion")
struct HoverRegionTests {
    @Test("노치 화면은 노치 오른쪽만")
    func notch() {
        #expect(HoverRegion.rect(for: builtin) == CGRect(x: 1064, y: 1205.5, width: 856, height: 37.5))
    }

    @Test("외장 모니터가 주 화면이어도 노치 오른쪽에서 펼친다")
    func notchOnSecondaryScreen() {
        #expect(HoverRegion.contains(CGPoint(x: 1500, y: -10), screens: externalFirst))
        #expect(!HoverRegion.contains(CGPoint(x: 500, y: -10), screens: externalFirst))
    }

    // 아이콘 위치는 주 화면(외장) 것만 읽혀서, 외장에서 잰 폭을 노치 오른쪽(856pt)에도 쓴다(실측)

    @Test("노치 오른쪽이 꽉 차 외장에서 잰 폭이 더 넓어도 노치 오른쪽 어디서든 펼친다")
    func overflowingNotchFallsBackToFull() {
        for statusWidth: CGFloat in [856, 1000, 1600] {
            #expect(HoverRegion.emptyRect(for: builtinBelow, statusWidth: statusWidth) == HoverRegion.rect(for: builtinBelow))
            #expect(HoverRegion.contains(CGPoint(x: 1070, y: -10), screens: externalFirst, statusWidth: statusWidth))
            #expect(HoverRegion.contains(CGPoint(x: 1910, y: -10), screens: externalFirst, statusWidth: statusWidth))
        }
    }

    @Test("거의 꽉 차 빈 곳이 24pt보다 좁으면 전체 영역, 24pt부터는 빈 곳만")
    func nearlyFullNotch() {
        // 오른쪽 끝(1920) - 폭 - 4 - 노치 오른쪽 시작(1064) = 빈 곳 폭
        #expect(HoverRegion.emptyRect(for: builtinBelow, statusWidth: 829) == HoverRegion.rect(for: builtinBelow))  // 23pt
        #expect(HoverRegion.emptyRect(for: builtinBelow, statusWidth: 828)
                == CGRect(x: 1064, y: -37.5, width: 24, height: 37.5))
        #expect(HoverRegion.contains(CGPoint(x: 1080, y: -10), screens: externalFirst, statusWidth: 828))
        #expect(!HoverRegion.contains(CGPoint(x: 1500, y: -10), screens: externalFirst, statusWidth: 828))  // 아이콘 위
    }

    // MARK: - 메뉴바 줄 전체 (펼친 뒤 유지하는 영역)

    @Test("펼친 뒤에는 노치 왼쪽까지 메뉴바 줄 전체에서 유지한다 — 넘친 아이콘(«)이 거기 펼쳐진다")
    func menuBarIncludesLeftOfNotch() {
        #expect(HoverRegion.inMenuBar(CGPoint(x: 300, y: -10), screens: externalFirst))   // 노치 왼쪽
        #expect(HoverRegion.inMenuBar(CGPoint(x: 1500, y: -10), screens: externalFirst))  // 노치 오른쪽
        #expect(HoverRegion.inMenuBar(CGPoint(x: 300, y: 1070), screens: externalFirst))  // 외장 왼쪽
        #expect(!HoverRegion.inMenuBar(CGPoint(x: 300, y: -50), screens: externalFirst))  // 메뉴바 아래
        #expect(!HoverRegion.inMenuBar(CGPoint(x: 300, y: 1000), screens: externalFirst))
    }

    // MARK: - 손쉬운 사용 좌표 (왼쪽 위 기준, y가 아래로)

    @Test("메뉴바 줄 위의 아이콘은 믿는다 — 외장 아래 내장 화면도")
    func onMenuBar() {
        #expect(HoverRegion.isOnMenuBar(axFrame: CGRect(x: 1470, y: 7, width: 45, height: 24), screens: externalFirst))
        // 내장(y -1243...0)의 메뉴바는 손쉬운 사용 좌표로 y 1080...1117.5
        #expect(HoverRegion.isOnMenuBar(axFrame: CGRect(x: 1470, y: 1087, width: 45, height: 24), screens: externalFirst))
        // 내장이 주 화면이고 외장이 위에 있으면 외장 메뉴바는 음수 y
        #expect(HoverRegion.isOnMenuBar(axFrame: CGRect(x: 1470, y: 7, width: 45, height: 24), screens: [builtin, external]))
        #expect(HoverRegion.isOnMenuBar(axFrame: CGRect(x: 1470, y: -1073, width: 45, height: 24), screens: [builtin, external]))
    }

    @Test("넘쳐서 안 그려진 아이콘의 엉뚱한 위치는 버린다(실측 x=-1, y=1231)")
    func overflowedIconIsNotOnMenuBar() {
        #expect(!HoverRegion.isOnMenuBar(axFrame: CGRect(x: -1, y: 1231, width: 38, height: 24), screens: [builtin]))
        #expect(!HoverRegion.isOnMenuBar(axFrame: CGRect(x: -1, y: 7, width: 0, height: 24), screens: [builtin]))
        #expect(!HoverRegion.isOnMenuBar(axFrame: CGRect(x: 1470, y: 500, width: 45, height: 24), screens: externalFirst))
    }

    @Test("노치 없는 화면은 메뉴바 오른쪽 절반")
    func noNotch() {
        #expect(HoverRegion.rect(for: external) == CGRect(x: 960, y: 2297, width: 960, height: 26))
    }

    @Test("앱 메뉴 쪽과 메뉴바 아래는 영역 밖")
    func contains() {
        let s = [builtin, external]
        #expect(HoverRegion.contains(CGPoint(x: 1500, y: 1230), screens: s))
        #expect(!HoverRegion.contains(CGPoint(x: 500, y: 1230), screens: s))
        #expect(HoverRegion.contains(CGPoint(x: 1900, y: 2310), screens: s))
        #expect(!HoverRegion.contains(CGPoint(x: 300, y: 2310), screens: s))
        #expect(!HoverRegion.contains(CGPoint(x: 1500, y: 1000), screens: s))
    }

    @Test("맨 위 모서리에 밀어붙여도 안으로 친다")
    func topEdge() {
        #expect(HoverRegion.contains(CGPoint(x: 1900, y: 2323), screens: [external]))
        #expect(HoverRegion.contains(CGPoint(x: 1919.9, y: 1243), screens: [builtin]))
    }

    @Test("화면이 빠지면 그 화면 영역은 사라진다")
    func screenRemoved() {
        #expect(!HoverRegion.contains(CGPoint(x: 1900, y: 2310), screens: [builtin]))
    }

    // MARK: - 빈 곳 (접혀 있을 때 펼치는 영역)
    // statusWidth: 화면 오른쪽 끝에서 가장 왼쪽 상태 아이콘까지의 폭

    @Test("빈 곳은 상태 아이콘 왼쪽까지만 — 아이콘(시계, Wi-Fi) 위에서는 펼치지 않는다")
    func emptyStopsBeforeIcons() {
        #expect(HoverRegion.emptyRect(for: external, statusWidth: 600) == CGRect(x: 960, y: 2297, width: 356, height: 26))
        #expect(HoverRegion.emptyRect(for: builtin, statusWidth: 600) == CGRect(x: 1064, y: 1205.5, width: 252, height: 37.5))
    }

    @Test("빈 곳이 거의 없으면(노치 오른쪽이 꽉 참) 전체 영역으로 — 펼칠 방법이 없어지면 안 된다")
    func emptyFallsBackWhenFull() {
        #expect(HoverRegion.emptyRect(for: builtin, statusWidth: 840) == HoverRegion.rect(for: builtin))
    }

    @Test("아이콘 폭을 아직 모르면 전체 영역")
    func emptyUnknownWidth() {
        #expect(HoverRegion.emptyRect(for: external, statusWidth: nil) == HoverRegion.rect(for: external))
    }

    @Test("빈 곳 판정")
    func containsEmpty() {
        let s = [builtin, external]
        #expect(HoverRegion.contains(CGPoint(x: 1200, y: 2310), screens: s, statusWidth: 600))   // 외장 빈 곳
        #expect(!HoverRegion.contains(CGPoint(x: 1500, y: 2310), screens: s, statusWidth: 600))  // 외장 아이콘 위
        #expect(HoverRegion.contains(CGPoint(x: 1500, y: 2310), screens: s, statusWidth: nil))   // 전체 영역
    }
}
