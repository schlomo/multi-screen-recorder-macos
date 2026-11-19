import Testing
@testable import RecorderCore

/// The recording log names the Mac's model identifier, not its name or serial number (D64).
@Suite struct MacModelTests {
    @Test func theMacModelIsAnIdentifier() throws {
        let model = try #require(macModel())
        #expect(model.wholeMatch(of: /[A-Za-z]+[0-9]+,[0-9]+/) != nil, "\(model)")
    }
}
