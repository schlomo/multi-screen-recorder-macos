import Foundation
import Testing
@testable import RecorderLogic

/// A problem goes into the manifest, which is written at once, and is told
/// once until it clears (D46).
@Suite struct ProblemsToldTests {
    private func manifest() -> RecordingManifest {
        RecordingManifest(app: "x", started: .now, timeZone: .current, settings: .defaults)
    }

    private func problem(_ at: Int64, _ text: String = "The free space cannot be read") -> RecordingProblem {
        RecordingProblem(at: at, problem: text, error: "denied")
    }

    /// A problem reported after the recording manifest was finalized changes it no more (D64).
    @Test func aProblemAfterTheEndIsNotAdded() {
        var told = ProblemsTold()
        var manifest = manifest()
        manifest.finalize(ended: .now, timeZone: .current)
        #expect(told.add(problem(1), kind: .recordingLogNotWritten, to: &manifest) == .afterTheEnd)
        #expect(manifest.problems.isEmpty)
        #expect(manifest.result == .ok)
    }

    @Test func aProblemIsAddedToldAndTheManifestWritten() {
        var told = ProblemsTold()
        var manifest = manifest()
        #expect(told.add(problem(1), kind: .freeSpaceNotRead, to: &manifest) == .tell(writeManifest: true))
        #expect(manifest.problems == [problem(1)])
    }

    /// Writing the manifest is what failed: writing it again at once would only fail again.
    @Test func aManifestThatCannotBeWrittenIsNotWrittenForItsOwnProblem() {
        var told = ProblemsTold()
        var manifest = manifest()
        #expect(told.add(problem(1, "Cannot write the recording manifest"), kind: .manifestNotWritten, to: &manifest)
            == .tell(writeManifest: false))
        #expect(manifest.problems.count == 1)
    }

    @Test func aRepeatingProblemIsToldOnceUntilItClears() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(1), kind: .freeSpaceNotRead, to: &manifest)
        #expect(told.add(problem(6), kind: .freeSpaceNotRead, to: &manifest) == .alreadyTold)
        #expect(told.add(problem(11), kind: .freeSpaceNotRead, to: &manifest) == .alreadyTold)
        #expect(manifest.problems == [problem(1)])
        // Another kind is told meanwhile.
        #expect(told.add(problem(12, "The screens cannot be read"), kind: .screensNotRead, to: &manifest) == .tell(writeManifest: true))
        told.cleared(.freeSpaceNotRead, at: 15)
        #expect(told.add(problem(20), kind: .freeSpaceNotRead, to: &manifest) == .tell(writeManifest: true))
        #expect(manifest.problems.count == 3)
    }

    // The status window's lines (D78): red when broken, orange for a hiccup in a recording that worked.

    private let second: Int64 = 1_000_000_000

    private func stall(_ told: inout ProblemsTold, _ manifest: inout RecordingManifest, at seconds: Double) {
        let problem = RecordingProblem(atSeconds: seconds, problem: "Camera BRIO", error: CameraTracker.stalledError)
        _ = told.add(problem, kind: .cameraStalled("brio"), to: &manifest)
    }

    private func nanoseconds(_ seconds: Double) -> Int64 { Int64((seconds * 1_000_000_000).rounded()) }

    /// A stall's file goes on: orange while it lasts and after.
    @Test func aStallIsOrangeAndTellsItsLengthAndItsStart() {
        var told = ProblemsTold()
        var manifest = manifest()
        stall(&told, &manifest, at: 55)
        #expect(told.lines(now: nanoseconds(56)) == [ProblemLine(text: "Camera BRIO stalled since 0:53", isRed: false)])
        told.cleared(.cameraStalled("brio"), at: nanoseconds(60.4), length: nanoseconds(7.4))
        #expect(told.lines(now: nanoseconds(61))
            == [ProblemLine(text: "Camera BRIO stalled 7.4 s at 0:53, recovered", isRed: false)])
    }

    @Test func repeatsOfAKindShareOneLine() {
        var told = ProblemsTold()
        var manifest = manifest()
        stall(&told, &manifest, at: 10)
        told.cleared(.cameraStalled("brio"), at: nanoseconds(12), length: nanoseconds(4))
        stall(&told, &manifest, at: 30)
        told.cleared(.cameraStalled("brio"), at: nanoseconds(33), length: nanoseconds(5))
        stall(&told, &manifest, at: 40)
        // The third is ongoing: 3 s since its start, 2 s before it was told.
        #expect(told.lines(now: nanoseconds(41)) == [ProblemLine(text: "Camera BRIO stalled 3 times, 12 s in total", isRed: false)])
        // A file of the camera starting ends the stall too, without its length.
        told.cleared(.cameraStalled("brio"), at: nanoseconds(41))
        #expect(told.lines(now: nanoseconds(50)) == [ProblemLine(text: "Camera BRIO stalled 3 times, 12 s in total, recovered", isRed: false)])
        #expect(manifest.problems.count == 3)
    }

    @Test func aProblemThatEndsTellsHowLongItLasted() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(12 * second), kind: .freeSpaceNotRead, to: &manifest)
        #expect(told.lines(now: 13 * second) == [ProblemLine(text: "The free space cannot be read since 0:12: denied", isRed: true)])
        told.cleared(.freeSpaceNotRead, at: 16 * second)
        #expect(told.lines(now: 20 * second)
            == [ProblemLine(text: "The free space cannot be read for 4.0 s at 0:12, recovered: denied", isRed: false)])
        _ = told.add(problem(3723 * second), kind: .freeSpaceNotRead, to: &manifest)
        #expect(told.lines(now: 3724 * second)
            == [ProblemLine(text: "The free space cannot be read 2 times, 5.0 s in total: denied", isRed: true)])
    }

    /// The owner's rule, per kind: red while it lasts when a source is not recorded or saved or a person
    /// must act, always for a damaged file; orange once over, and always for what never touches the recording.
    @Test(arguments: [
        (ProblemKind.cameraPermissionMissing, true, false), (.screenNotCaptured("S"), true, false),
        (.cameraNotCaptured("C"), true, false), (.audioSourceFailed("A"), true, false), (.audioFileFailed("f"), true, false),
        (.recordingLogNotWritten, true, false), (.manifestNotWritten, true, false), (.freeSpaceNotRead, true, false),
        (.screensNotRead, true, false), (.audioInputsNotRead, true, false),
        (.audioFileLost("f"), true, true), (.audioInputChangesNotFollowed, true, true), (.audioInputNotRecordable("A"), true, true),
        (.cameraStalled("C"), false, false), (.dockIconNotShown, false, false), (.inputVolumeNotSet("A"), false, false),
        (.inputVolumeNotFollowed("A"), false, false), (.timelineFileNotWritten, false, false),
    ])
    func theColourFollowsTheKindAndWhetherItLasts(kind: ProblemKind, redWhileItLasts: Bool, redOnceOver: Bool) {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(second), kind: kind, to: &manifest)
        #expect(told.lines(now: 2 * second).first?.isRed == redWhileItLasts)
        told.cleared(kind, at: 3 * second)
        #expect(told.lines(now: 4 * second).first?.isRed == redOnceOver)
    }

    /// Red first, then orange, each newest first.
    @Test func redLinesComeFirstEachGroupNewestFirst() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(1 * second, "Screen A"), kind: .screenNotCaptured("A"), to: &manifest)
        _ = told.add(problem(2 * second, "The Dock icon cannot be shown"), kind: .dockIconNotShown, to: &manifest)
        _ = told.add(problem(3 * second, "Screen B"), kind: .screenNotCaptured("B"), to: &manifest)
        _ = told.add(problem(4 * second, "Volume"), kind: .inputVolumeNotSet("M"), to: &manifest)
        #expect(told.lines(now: 5 * second).map(\.text) == [
            "Screen B since 0:03: denied", "Screen A since 0:01: denied",
            "Volume since 0:04: denied", "The Dock icon cannot be shown since 0:02: denied",
        ])
    }

    /// One decimal below 10 s (as rounded), whole seconds from there, m:ss from a minute on.
    @Test func lengthsAreShownAsTheyRound() {
        for (length, shown) in [(9.94, "9.9 s"), (9.96, "10 s"), (59.6, "1:00"), (125.0, "2:05")] {
            var told = ProblemsTold()
            var manifest = manifest()
            _ = told.add(problem(0), kind: .freeSpaceNotRead, to: &manifest)
            told.cleared(.freeSpaceNotRead, at: nanoseconds(length))
            #expect(told.lines(now: nanoseconds(length)).first?.text == "The free space cannot be read for \(shown) at 0:00, recovered: denied")
        }
    }

    /// Following the audio inputs' changes failing is its own problem: a working read of them does not end it.
    @Test func changesOfTheAudioInputsNotFollowedIsNotEndedByAReadOfThem() {
        var told = ProblemsTold()
        var manifest = manifest()
        let notFollowed = RecordingProblem(atSeconds: 0, problem: "Changes of the audio inputs cannot be followed", error: "denied")
        _ = told.add(notFollowed, kind: .audioInputChangesNotFollowed, to: &manifest)
        told.cleared(.audioInputsNotRead, at: 5 * second)
        #expect(told.add(problem(6 * second, "The audio inputs cannot be read"), kind: .audioInputsNotRead, to: &manifest)
            == .tell(writeManifest: true))
        #expect(told.lines(now: 7 * second).last
            == ProblemLine(text: "Changes of the audio inputs cannot be followed since 0:00: denied", isRed: true))
    }
}
