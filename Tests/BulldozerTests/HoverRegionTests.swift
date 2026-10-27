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

@Suite("HoverRegion")
struct HoverRegionTests {
    @Test("노치 화면은 노치 오른쪽만")
    func notch() {
        #expect(HoverRegion.rect(for: builtin) == CGRect(x: 1064, y: 1205.5, width: 856, height: 37.5))
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
