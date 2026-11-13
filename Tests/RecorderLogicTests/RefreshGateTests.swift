import Testing
@testable import RecorderLogic

@Suite struct RefreshGateTests {
    @Test func aChangeRefreshesAtOnceWhileNoMenuIsOpen() {
        var gate = RefreshGate()
        let result1 = gate.changeArrived()
        #expect(result1)
        let result2 = gate.changeArrived()
        #expect(result2)
    }

    @Test func aChangeWhileAMenuIsOpenWaitsForTheMenuToClose() {
        var gate = RefreshGate()
        gate.menuOpened()
        let result3 = gate.changeArrived()
        #expect(!result3)
        let result4 = gate.changeArrived()
        #expect(!result4)
        let result5 = gate.menuClosed()
        #expect(result5)
        let result6 = gate.changeArrived()
        #expect(result6)
    }

    @Test func aMenuThatClosesWithoutAChangeRefreshesNothing() {
        var gate = RefreshGate()
        gate.menuOpened()
        let result7 = gate.menuClosed()
        #expect(!result7)
    }

    @Test func nestedMenusCountAsOpenUntilTheLastCloses() {
        var gate = RefreshGate()
        gate.menuOpened()
        gate.menuOpened()
        let result8 = gate.changeArrived()
        #expect(!result8)
        let result9 = gate.menuClosed()
        #expect(!result9)
        let result10 = gate.changeArrived()
        #expect(!result10)
        let result11 = gate.menuClosed()
        #expect(result11)
    }

    @Test func aCloseWithoutAnOpenIsHarmless() {
        var gate = RefreshGate()
        let result12 = gate.menuClosed()
        #expect(!result12)
        let result13 = gate.changeArrived()
        #expect(result13)
    }
}
