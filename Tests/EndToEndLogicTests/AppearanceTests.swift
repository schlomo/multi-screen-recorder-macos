import Testing
@testable import EndToEndLogic

@Suite struct AppearanceTests {
    @Test func darkIsTakenOnlyInTheThrowawayVM() {
        #expect(Appearance.taken(inThrowawayVM: false) == [.light])
        #expect(Appearance.taken(inThrowawayVM: true) == [.light, .dark])
    }
}
