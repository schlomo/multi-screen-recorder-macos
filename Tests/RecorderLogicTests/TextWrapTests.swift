import Testing
@testable import RecorderLogic

@Suite struct TextWrapTests {
    private func words(_ lengths: [Int]) -> String {
        lengths.map { String(repeating: "x", count: $0) }.joined(separator: " ")
    }

    /// A line of exactly the width stays whole; one more character wraps.
    @Test func aLineOfExactlyTheWidthIsNotWrappedAndOneMoreIs() {
        #expect(wrappedLines(words([39, 40]), width: 80) == [words([39, 40])])
        #expect(wrappedLines(words([40, 40]), width: 80) == [words([40]), words([40])])
        #expect(wrappedLines(words([39, 40]), width: 79) == [words([39]), words([40])])
    }

    @Test func aWordLongerThanTheWidthStaysWhole() {
        #expect(wrappedLines(words([100, 3]), width: 80) == [words([100]), "xxx"])
        #expect(wrappedLines("", width: 80).isEmpty)
    }
}
