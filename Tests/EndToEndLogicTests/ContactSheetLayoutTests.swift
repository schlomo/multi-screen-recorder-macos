import Testing
@testable import EndToEndLogic

@Suite struct ContactSheetLayoutTests {
    @Test func stillsFillRowsOfThreeUnderTheirLabels() {
        let layout = ContactSheetLayout(count: 4)
        #expect(layout.columns == 3)
        #expect(layout.rows == 2)
        #expect(layout.width == 3 * 480)
        #expect(layout.height == 2 * (270 + 24))
        // Top-left origins: the label above, the still below it.
        #expect(layout.cell(0) == .init(x: 0, y: 0))
        #expect(layout.cell(2) == .init(x: 960, y: 0))
        #expect(layout.cell(3) == .init(x: 0, y: 294))
    }

    @Test func fewerStillsThanColumnsMakeANarrowerSheet() {
        let layout = ContactSheetLayout(count: 2)
        #expect(layout.columns == 2)
        #expect(layout.width == 960)
        #expect(layout.height == 294)
    }

    @Test func aStillIsFittedIntoItsCellKeepingItsShape() {
        let layout = ContactSheetLayout(count: 1)
        #expect(layout.fit(width: 3840, height: 2160) == .init(x: 0, y: 0, width: 480, height: 270))
        #expect(layout.fit(width: 3440, height: 1440) == .init(x: 0, y: 34, width: 480, height: 201))
        #expect(layout.fit(width: 1080, height: 1920) == .init(x: 164, y: 0, width: 152, height: 270))
    }
}
