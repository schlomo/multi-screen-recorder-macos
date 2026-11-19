import AVFoundation
import RecorderLogic
import Testing
@testable import RecorderCore

/// A writer's error keeps what macOS gave, its code included (D64): the CI
/// run of PR #23 said only "The operation could not be completed".
@Suite struct WriterErrorTests {
    private let avError = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue, userInfo: [
        NSLocalizedDescriptionKey: "The operation could not be completed",
        NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -12912),
    ])

    @Test func aScreenFileWritersErrorKeepsTheChain() {
        let error = ScreenFileWriterError(avError, while: "cannot write f.mov")
        #expect(error.detail == ErrorDetail(message: "cannot write f.mov", underlying: [ErrorDetail(avError)]))
        #expect(error.description.hasPrefix("cannot write f.mov: The operation could not be completed (AVFoundationErrorDomain -11800)"))
        #expect(error.description.hasSuffix("(NSOSStatusErrorDomain -12912)"))
        #expect(!error.isDiskFull)
        #expect(ErrorDetail(error) == error.detail)
    }

    @Test func anAudioFileWritersErrorKeepsTheChain() {
        let error = AudioFileWriterError(avError, while: "cannot write a.mov")
        #expect(error.detail == ErrorDetail(message: "cannot write a.mov", underlying: [ErrorDetail(avError)]))
        #expect(error.description.contains("(AVFoundationErrorDomain -11800)"))
    }

    @Test func aFullDiskDeepInTheChainIsAFullDisk() {
        let full = NSError(domain: AVFoundationErrorDomain, code: -11800, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)),
        ])
        #expect(ScreenFileWriterError(full, while: "cannot write f.mov").isDiskFull)
        #expect(AudioFileWriterError(full, while: "cannot write a.mov").isDiskFull)
    }
}
