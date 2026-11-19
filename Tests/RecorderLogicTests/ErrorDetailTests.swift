import Foundation
import Testing
@testable import RecorderLogic

private struct PlainSwiftError: Error, CustomStringConvertible {
    var description: String { "the plain error says this" }
}

private struct NamelessSwiftError: Error {}

private struct LocalizedSwiftError: LocalizedError {
    var errorDescription: String? { "the localized text" }
    var failureReason: String? { "the reason" }
    var recoverySuggestion: String? { "try again" }
}

private struct Detailed: ErrorWithDetail {
    let detail: ErrorDetail
}

/// Every error, also one nobody foresaw, with its full chain (D64).
@Suite struct ErrorDetailTests {
    /// The shape of the CI run of PR #23: AVFoundation's error with an
    /// OSStatus underneath, which only said "The operation could not be completed".
    private let writerError = NSError(domain: AVFoundationErrorDomainName, code: -11800, userInfo: [
        NSLocalizedDescriptionKey: "The operation could not be completed",
        NSLocalizedFailureReasonErrorKey: "An unknown error occurred (-12912)",
        NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -12912, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 28),
        ]),
    ])

    @Test func theChainKeepsEveryLevelWithItsDomainAndCode() {
        let detail = ErrorDetail(writerError)
        #expect(detail.domain == AVFoundationErrorDomainName)
        #expect(detail.code == -11800)
        #expect(detail.description == "The operation could not be completed")
        #expect(detail.reason == "An unknown error occurred (-12912)")
        #expect(detail.underlying.map(\.domain) == [NSOSStatusErrorDomain])
        #expect(detail.underlying[0].code == -12912)
        #expect(detail.underlying[0].underlying.map(\.domain) == [NSPOSIXErrorDomain])
        #expect(detail.underlying[0].underlying[0].code == 28)
        #expect(detail.underlying[0].underlying[0].underlying == [])
        #expect(detail.text.hasPrefix(
            "The operation could not be completed (AVFoundationErrorDomain -11800; reason: An unknown error occurred (-12912)): "))
        #expect(detail.text.contains("(NSOSStatusErrorDomain -12912)"))
        #expect(detail.text.hasSuffix("(NSPOSIXErrorDomain 28; reason: No space left on device)"))
    }

    @Test func multipleUnderlyingErrorsAreAllKept() {
        let error = NSError(domain: "Outer", code: 1, userInfo: [
            NSMultipleUnderlyingErrorsKey: [NSError(domain: "First", code: 2), NSError(domain: "Second", code: 3)],
        ])
        #expect(ErrorDetail(error).underlying.map(\.domain) == ["First", "Second"])
    }

    @Test func aWrappingMessageKeepsTheErrorUnderIt() {
        let detail = ErrorDetail(message: "cannot write a.mov", underlying: writerError)
        #expect(detail.domain == ErrorDetail.ownDomain)
        #expect(detail.underlying == [ErrorDetail(writerError)])
        #expect(detail.text.hasPrefix("cannot write a.mov: The operation could not be completed (AVFoundationErrorDomain -11800"))
        #expect(ErrorDetail(message: "cannot write a.mov", underlying: nil).text == "cannot write a.mov")
    }

    @Test(arguments: [
        (1_852_797_029, "1852797029 ('nope')"),
        (560_947_818, "560947818 ('!obj')"),
        (-50, "-50"),
        (0, "0"),
        (1, "1"),
        (Int(UInt32.max) + 1, "4294967296"),
    ])
    func anOSStatusShowsItsFourCharacterCodeWhereItHasOne(code: Int, text: String) {
        #expect(ErrorDetail.codeText(code) == text)
    }

    @Test func anOSStatusErrorSaysItsFourCharacterCode() {
        let detail = ErrorDetail(NSError(domain: NSOSStatusErrorDomain, code: 1_852_797_029))
        #expect(detail.text.contains("(NSOSStatusErrorDomain 1852797029 ('nope'))"))
    }

    @Test func theDepthGuardStopsAChainThatGoesOnAndSaysSo() {
        var error = NSError(domain: "Level", code: 100)
        for level in (0..<100).reversed() {
            error = NSError(domain: "Level", code: level, userInfo: [NSUnderlyingErrorKey: error])
        }
        var detail = ErrorDetail(error)
        var levels = 1
        while let next = detail.underlying.first, next.domain == "Level" {
            detail = next
            levels += 1
        }
        #expect(levels == ErrorDetail.maximumDepth + 1)
        #expect(detail.underlying.isEmpty)
        #expect(detail.truncated)
        #expect(detail.text.hasSuffix(": … (deeper underlying errors left out)"))
        let object = try? JSONSerialization.jsonObject(with: prettyJSON(detail)) as? [String: Any]
        #expect(object?["truncated"] as? Bool == true)
        #expect(!ErrorDetail(NSError(domain: "Level", code: 1)).truncated)
    }

    /// A recording log entry stays one line.
    @Test func lineBreaksInAnErrorBecomeOneLine() {
        let error = NSError(domain: "Multi", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "first\nsecond\r\nthird\rfourth",
            NSLocalizedFailureReasonErrorKey: "a\nb",
        ])
        let text = ErrorDetail(error).text
        #expect(text == "first⏎second⏎third⏎fourth (Multi 1; reason: a⏎b)")
        #expect(ErrorDetail(message: "x", underlying: [ErrorDetail(error)]).text.contains("first⏎second"))
    }

    @Test func aSwiftErrorSaysItsOwnTextNotTheBridgedOne() {
        #expect(ErrorDetail(PlainSwiftError()).description == "the plain error says this")
        #expect(ErrorDetail(NamelessSwiftError()).description.contains("NamelessSwiftError"))
        let localized = ErrorDetail(LocalizedSwiftError())
        #expect(localized.description == "the localized text")
        #expect(localized.reason == "the reason")
        #expect(localized.suggestion == "try again")
        #expect(localized.text.contains("reason: the reason; suggestion: try again"))
    }

    @Test func theRecordersOwnErrorsShowNoDomain() {
        #expect(ErrorDetail(DeviceReadError("the list of screens cannot be read")).text == "the list of screens cannot be read")
        #expect(ErrorDetail(message: "the disk is full").text == "the disk is full")
        #expect(ErrorDetail(PlainSwiftError()).text.contains("RecorderLogicTests."))
    }

    @Test func anErrorWithItsDetailIsTakenAsItIs() {
        let detail = ErrorDetail(message: "cannot create a.mov", underlying: writerError)
        #expect(ErrorDetail(Detailed(detail: detail)) == detail)
    }

    @Test func theValueForTheManifestLeavesOutWhatIsNot() throws {
        let detail = ErrorDetail(message: "cannot write a.mov", underlying: writerError)
        let object = try #require(try JSONSerialization.jsonObject(with: prettyJSON(detail)) as? [String: Any])
        #expect(Set(object.keys) == ["domain", "code", "description", "underlying"])
        let underlying = try #require((object["underlying"] as? [[String: Any]])?.first)
        #expect(Set(underlying.keys) == ["domain", "code", "description", "reason", "underlying"])
        #expect(underlying["code"] as? Int == -11800)
        #expect(try JSONDecoder().decode(ErrorDetail.self, from: prettyJSON(detail)) == detail)
    }
}

/// `AVFoundationErrorDomain`, which RecorderLogic does not import.
private let AVFoundationErrorDomainName = "AVFoundationErrorDomain"
