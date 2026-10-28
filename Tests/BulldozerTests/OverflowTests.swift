import CoreGraphics
import Testing
@testable import Bulldozer

// 실측 배치(내장 화면, 노치 오른쪽 1064~): « 1087.5, 앱 아이콘, 시스템 아이콘(1558~)
private func item(_ bundle: String, _ x: CGFloat, _ width: CGFloat = 24) -> StatusItemInfo {
    StatusItemInfo(bundleID: bundle, frame: CGRect(x: x, y: 7, width: width, height: 24))
}
private let button = CGRect(x: 1087.5, y: 1, width: 17.5, height: 36)
private let system = [item("com.apple.MenuBarAgent", 1558, 22), item("com.apple.MenuBarAgent", 1750, 150)]

@Suite("Overflow")
struct OverflowTests {
    @Test("닫혀 있으면 « 왼쪽에 앱 아이콘이 없다")
    func closed() {
        #expect(!Overflow.isOpen(button: button, shown: [item("a", 1111), item("b", 1145)] + system))
    }

    @Test("열리면 넘친 아이콘이 « 왼쪽(노치 왼쪽)에 놓인다")
    func open() {
        #expect(Overflow.isOpen(button: button, shown: [item("f", 620), item("g", 655), item("a", 1111)] + system))
    }

    @Test("시스템 아이콘은 열림 판정에 쓰지 않는다")
    func ignoresSystemItems() {
        #expect(!Overflow.isOpen(button: button, shown: [item("com.apple.MenuBarAgent", 600)] + system))
    }
}
