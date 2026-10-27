import Foundation
import Testing
@testable import Bulldozer

/// 0초부터 0.1초 머물러 펼친 상태를 만든다
private func expandedMachine() -> BarMachine {
    var m = BarMachine()
    m.pointer(inBar: true, at: 0)
    m.pointer(inBar: true, at: 0.1)
    return m
}

@Suite("BarMachine")
struct BarMachineTests {
    @Test("0.1초 머물면 펼친다")
    func expandAfterDelay() {
        var m = BarMachine()
        m.pointer(inBar: true, at: 0)
        m.pointer(inBar: true, at: 0.09)
        #expect(m.state == .collapsed)
        m.pointer(inBar: true, at: 0.1)
        #expect(m.state == .expanded)
    }

    @Test("스쳐 지나가면 안 펼친다")
    func passingThrough() {
        var m = BarMachine()
        m.pointer(inBar: true, at: 0)
        m.pointer(inBar: false, at: 0.05)
        m.pointer(inBar: true, at: 0.1)
        #expect(m.state == .collapsed)
    }

    @Test("벗어나고 0.5초 뒤 접는다")
    func collapseAfterLeaving() {
        var m = expandedMachine()
        m.pointer(inBar: false, at: 1.0)
        m.pointer(inBar: false, at: 1.49)
        #expect(m.state == .expanded)
        m.pointer(inBar: false, at: 1.5)
        #expect(m.state == .collapsed)
    }

    @Test("잠깐 벗어났다 돌아오면 유지")
    func briefLeave() {
        var m = expandedMachine()
        m.pointer(inBar: false, at: 1.0)
        m.pointer(inBar: true, at: 1.3)
        m.pointer(inBar: false, at: 1.6)
        m.pointer(inBar: false, at: 2.0)
        #expect(m.state == .expanded)
    }

    @Test("영역 안을 클릭한 뒤엔 벗어나도 유지 — 숨겼던 아이콘의 메뉴를 쓰는 중")
    func pinnedByClick() {
        var m = expandedMachine()
        m.clickedInBar()
        m.pointer(inBar: false, at: 1.0)
        m.pointer(inBar: false, at: 10.0)
        #expect(m.state == .expanded)
    }

    @Test("밖을 클릭하면 0.5초 뒤 접는다")
    func unpinByOutsideClick() {
        var m = expandedMachine()
        m.clickedInBar()
        m.pointer(inBar: false, at: 5.0)
        m.clickedOutsideBar(at: 10.0)
        m.pointer(inBar: false, at: 10.49)
        #expect(m.state == .expanded)
        m.pointer(inBar: false, at: 10.5)
        #expect(m.state == .collapsed)
    }

    @Test("접힌 상태 클릭은 고정하지 않는다")
    func clickWhileCollapsed() {
        var m = BarMachine()
        m.clickedInBar()
        m.pointer(inBar: true, at: 0)
        m.pointer(inBar: true, at: 0.1)
        m.pointer(inBar: false, at: 1.0)
        m.pointer(inBar: false, at: 1.5)
        #expect(m.state == .collapsed)
    }

    @Test("구분자 클릭은 펼침과 전부 펼침을 오간다")
    func separatorToggle() {
        var collapsed = BarMachine()
        collapsed.separatorClicked()
        #expect(collapsed.state == .collapsed)

        var m = expandedMachine()
        m.separatorClicked()
        #expect(m.state == .expandedAll)
        m.separatorClicked()
        #expect(m.state == .expanded)
    }

    @Test("전부 펼침도 벗어나면 접힌다")
    func collapseFromAll() {
        var m = expandedMachine()
        m.separatorClicked()
        m.pointer(inBar: false, at: 1.0)
        m.pointer(inBar: false, at: 1.5)
        #expect(m.state == .collapsed)
    }

    @Test("접혔다가 다시 펼치면 고정은 풀려 있다")
    func pinResetOnCollapse() {
        var m = expandedMachine()
        m.clickedInBar()
        m.clickedOutsideBar(at: 1.0)
        m.pointer(inBar: false, at: 1.5)
        #expect(m.state == .collapsed)
        m.pointer(inBar: true, at: 3.0)
        m.pointer(inBar: true, at: 3.25)  // 3.1 - 3.0은 부동소수점으로 0.1보다 작게 나올 수 있다
        #expect(m.state == .expanded)
        m.pointer(inBar: false, at: 4.0)
        m.pointer(inBar: false, at: 4.5)
        #expect(m.state == .collapsed)
    }

    // MARK: - 클릭 모드

    @Test("클릭 모드: 호버로는 펼치지 않는다")
    func clickModeIgnoresHover() {
        var m = BarMachine(mode: .click)
        m.pointer(inBar: true, at: 0)
        m.pointer(inBar: true, at: 5)
        #expect(m.state == .collapsed)
    }

    @Test("클릭 모드: 구분자 클릭은 한 단계씩 더 펼치고, 끝에서 누르면 접는다")
    func clickModeSteps() {
        var m = BarMachine(mode: .click)
        m.separatorClicked()
        #expect(m.state == .expanded)
        m.separatorClicked()
        #expect(m.state == .expandedAll)
        m.separatorClicked()
        #expect(m.state == .collapsed)
    }


    @Test("클릭 모드: 메뉴바를 벗어나도 유지, 밖을 클릭하면 바로 접는다")
    func clickModeCollapsesOnOutsideClick() {
        var m = BarMachine(mode: .click)
        m.separatorClicked()
        m.pointer(inBar: false, at: 1)
        m.pointer(inBar: false, at: 10)
        #expect(m.state == .expanded)
        m.clickedOutsideBar(at: 11)
        #expect(m.state == .collapsed)
    }

    @Test("클릭 모드: 펼친 채 메뉴바 안 아이콘을 클릭하면(메뉴 사용) 밖을 클릭할 때까지 유지")
    func clickModeInBarClick() {
        var m = BarMachine(mode: .click)
        m.separatorClicked()
        m.clickedInBar()
        m.pointer(inBar: false, at: 10)
        #expect(m.state == .expanded)
        m.clickedOutsideBar(at: 11)
        #expect(m.state == .collapsed)
    }


    @Test("모드를 바꾸면 접힌 상태로 돌아간다")
    func modeChangeCollapses() {
        var m = expandedMachine()
        m.mode = .click
        #expect(m.state == .collapsed)
    }

    // MARK: - 우클릭 메뉴

    @Test("메뉴가 닫히는 건 밖 클릭이 아니다 — 클릭 모드에서 메뉴를 닫자마자 접히면 안 된다")
    func menuCloseDoesNotCollapseClickMode() {
        var m = BarMachine(mode: .click)
        m.separatorClicked()
        m.clickedInBar()           // 메뉴 열림
        m.menuClosed(at: 1)
        #expect(m.state == .expanded)
    }

    @Test("호버 모드: 메뉴가 닫히면 고정이 풀려 벗어나면 다시 접힌다")
    func menuCloseUnpinsHoverMode() {
        var m = expandedMachine()
        m.clickedInBar()
        m.menuClosed(at: 1)
        m.pointer(inBar: false, at: 1)
        m.pointer(inBar: false, at: 1.5)
        #expect(m.state == .collapsed)
    }
}
