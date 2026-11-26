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
        _ = told.add(problem, kind: .cameraStalled("brio"), source: "BRIO", to: &manifest)
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

    /// A camera unplugged while stalled: its stall ends there, then disconnected.
    @Test func aStallEndedByAnUnplugSaysSo() {
        var told = ProblemsTold()
        var manifest = manifest()
        stall(&told, &manifest, at: 150)
        told.cleared(.cameraStalled("brio"), at: nanoseconds(151.4), ending: .disconnected)
        #expect(told.lines(now: nanoseconds(152))
            == [ProblemLine(text: "Camera BRIO stalled 3.4 s at 2:28, then disconnected", isRed: false)])
    }

    /// Repeats of a kind share one line, with other kinds told between them.
    @Test func repeatsOfAKindShareOneLine() {
        var told = ProblemsTold()
        var manifest = manifest()
        stall(&told, &manifest, at: 10)
        told.cleared(.cameraStalled("brio"), at: nanoseconds(12), length: nanoseconds(4))
        _ = told.add(problem(20 * second, "The screens cannot be read"), kind: .screensNotRead, to: &manifest)
        stall(&told, &manifest, at: 30)
        told.cleared(.cameraStalled("brio"), at: nanoseconds(33), length: nanoseconds(5))
        stall(&told, &manifest, at: 40)
        // The third is ongoing: 3 s since its start, 2 s before it was told.
        #expect(told.lines(now: nanoseconds(41)) == [
            ProblemLine(text: "Screens not read since 0:20: denied", isRed: true),
            ProblemLine(text: "Camera BRIO stalled 3 times, 12 s in total", isRed: false),
        ])
        // A file of the camera starting ends the stall too, without its length.
        told.cleared(.cameraStalled("brio"), at: nanoseconds(41))
        #expect(told.lines(now: nanoseconds(50)).last
            == ProblemLine(text: "Camera BRIO stalled 3 times, 12 s in total, recovered", isRed: false))
        #expect(manifest.problems.count == 4)
    }

    @Test func aProblemThatEndsTellsHowLongItLasted() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(12 * second), kind: .freeSpaceNotRead, to: &manifest)
        #expect(told.lines(now: 13 * second) == [ProblemLine(text: "Free space not read since 0:12: denied", isRed: true)])
        told.cleared(.freeSpaceNotRead, at: 16 * second)
        #expect(told.lines(now: 20 * second)
            == [ProblemLine(text: "Free space not read for 4.0 s at 0:12, recovered: denied", isRed: false)])
        _ = told.add(RecordingProblem(at: 3723 * second, problem: "x", error: "gone"), kind: .freeSpaceNotRead, to: &manifest)
        #expect(told.lines(now: 3724 * second)
            == [ProblemLine(text: "Free space not read 2 times, 5.0 s in total: latest: gone", isRed: true)])
    }

    /// Each kind's own words; a kind keyed by an ID names its source as told.
    @Test func eachKindHasItsOwnPhrase() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(12 * second, "Screen DELL"), kind: .screenNotCaptured("U"), source: "DELL", to: &manifest)
        told.cleared(.screenNotCaptured("U"), at: 14 * second, ending: .disconnected)
        _ = told.add(problem(20 * second, "x"), kind: .audioInputNotRecordable("Razer"), to: &manifest)
        told.show(problem(21 * second, "y"), kind: .guideTracksCut("Screen 1 - DELL.mov"))
        #expect(told.lines(now: 30 * second).map(\.text) == [
            "Audio input Razer not recordable since 0:20: denied",
            "Guide tracks of Screen 1 - DELL.mov cut since 0:21: denied",
            "Screen DELL not captured for 2.0 s at 0:12, then disconnected: denied",
        ])
    }

    /// A line only shown, as a video file's end, keeps no tell of its kind from the manifest; and only a
    /// failure that ends with a new file can be over when told: a full disk or cut guide tracks never are.
    @Test func aShownLineNeitherSwallowsATellNorEndsWhatANewFileDoesNotEnd() {
        var told = ProblemsTold()
        var manifest = manifest()
        told.show(problem(5 * second, "Camera file c.mov"), kind: .cameraNotCaptured("C"), source: "BRIO")
        #expect(told.add(problem(5 * second, "Camera BRIO stream failed"), kind: .cameraNotCaptured("C"), source: "BRIO", to: &manifest)
            == .tell(writeManifest: true))
        #expect(manifest.problems.count == 1)
        #expect(told.add(problem(6 * second, "Camera BRIO"), kind: .cameraNotCaptured("C"), source: "BRIO", to: &manifest) == .alreadyTold)
        told.show(problem(5 * second, "g"), kind: .guideTracksCut("Screen 1 - DELL.mov"), endedAt: 6 * second)
        told.show(problem(5 * second, "d"), kind: .diskFull, endedAt: 6 * second)
        #expect(told.lines(now: 7 * second).map(\.text) == [
            "Disk full since 0:05: denied", "Camera BRIO not captured since 0:05: denied",
            "Guide tracks of Screen 1 - DELL.mov cut since 0:05: denied",
        ])
    }

    /// A stall whose capture ended neither by its frames coming again nor by an unplug: ended.
    @Test func aStallEndedWithItsCaptureSaysStopped() {
        var told = ProblemsTold()
        var manifest = manifest()
        stall(&told, &manifest, at: 30)
        told.cleared(.cameraStalled("brio"), at: nanoseconds(31), ending: .stopped)
        #expect(told.lines(now: nanoseconds(32)).map(\.text) == ["Camera BRIO stalled 3.0 s at 0:28, stopped"])
    }

    /// A failure of a file whose source already has a newer file is over when told: orange at once.
    @Test func aFailureToldAfterANewerFileIsOverAtOnce() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(5 * second, "f"), kind: .audioFileFailed("a.mov"), endedAt: 6 * second, to: &manifest)
        #expect(told.lines(now: 7 * second) == [ProblemLine(text: "File a.mov failed for 1.0 s at 0:05, recovered: denied", isRed: false)])
        #expect(manifest.problems.count == 1)
    }

    /// The owner's rule, per kind: red while it lasts when a source is not recorded or saved or a person
    /// must act, always for a damaged file; orange once over, and always for what never touches the recording.
    @Test(arguments: [
        (ProblemKind.cameraPermissionMissing, true, false), (.screenNotCaptured("S"), true, false),
        (.cameraNotCaptured("C"), true, false), (.audioSourceFailed("A"), true, false), (.audioFileFailed("f"), true, false),
        (.recordingLogNotWritten, true, false), (.manifestNotWritten, true, false), (.freeSpaceNotRead, true, false),
        (.screensNotRead, true, false), (.audioInputsNotRead, true, false), (.diskFull, true, false),
        (.audioFileLost("f"), true, true), (.videoFileLost("f"), true, true), (.audioInputChangesNotFollowed, true, true),
        (.audioInputNotRecordable("A"), true, true),
        (.cameraStalled("C"), false, false), (.dockIconNotShown, false, false), (.inputVolumeNotSet("A"), false, false),
        (.inputVolumeNotFollowed("A"), false, false), (.timelineFileNotWritten, false, false), (.guideTracksCut("f"), false, false),
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
        _ = told.add(problem(1 * second), kind: .screenNotCaptured("A"), source: "A", to: &manifest)
        _ = told.add(problem(2 * second), kind: .dockIconNotShown, to: &manifest)
        _ = told.add(problem(3 * second), kind: .screenNotCaptured("B"), source: "B", to: &manifest)
        _ = told.add(problem(4 * second), kind: .inputVolumeNotSet("M"), to: &manifest)
        #expect(told.lines(now: 5 * second).map(\.text) == [
            "Screen B not captured since 0:03: denied", "Screen A not captured since 0:01: denied",
            "Input volume of M not set since 0:04: denied", "Dock icon not shown since 0:02: denied",
        ])
    }

    /// One decimal below 10 s (as rounded), whole seconds from there, m:ss from a minute on.
    @Test func lengthsAreShownAsTheyRound() {
        for (length, shown) in [(9.94, "9.9 s"), (9.96, "10 s"), (10.45, "10 s"), (59.6, "1:00"), (125.0, "2:05")] {
            var told = ProblemsTold()
            var manifest = manifest()
            _ = told.add(problem(0), kind: .freeSpaceNotRead, to: &manifest)
            told.cleared(.freeSpaceNotRead, at: nanoseconds(length))
            #expect(told.lines(now: nanoseconds(length)).first?.text == "Free space not read for \(shown) at 0:00, recovered: denied")
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
            == ProblemLine(text: "Changes of the audio inputs not followed since 0:00: denied", isRed: true))
    }

    /// An audio input silent right after its gaps: red with what to do while it lasts, orange in the past once
    /// its sound returns or it disconnects; counted as any broken source (D81).
    @Test func anAudioInputSilentAfterItsGapsIsRedUntilItsSoundReturns() {
        var told = ProblemsTold()
        var manifest = manifest()
        let kind = ProblemKind.audioInputSilentAfterGaps("B")
        let silent = RecordingProblem(at: 31 * second, problem: "The audio input BRIO sends only silence after its gaps", error: nil)
        #expect(told.add(silent, kind: kind, source: "Audio 3 BRIO", note: "0:25", to: &manifest) == .tell(writeManifest: true))
        #expect(told.lines(now: 45 * second) == [ProblemLine(
            text: "Audio 3 BRIO sends only silence since its gaps at 0:25; unplug and plug it in again", isRed: true)])
        told.cleared(kind, at: 96 * second)
        #expect(told.lines(now: 100 * second) == [ProblemLine(
            text: "Audio 3 BRIO sent only silence for 1:05 after its gaps at 0:25, recovered", isRed: false)])
        _ = told.add(silent, kind: kind, source: "Audio 3 BRIO", note: "0:25", to: &manifest)
        told.cleared(kind, at: 40 * second, ending: .disconnected)
        #expect(told.lines(now: 100 * second).first?.text == "Audio 3 BRIO sent only silence for 9.0 s after its gaps at 0:25, then disconnected")
    }

    /// The gaps no audio follows: the first gap of the input from `silenceAfterGapsTime` before its zeros
    /// began up to when no audio started; none without such a gap (D81).
    @Test func noAudioRightAfterGapsFindsTheFirstOfThem() {
        func gap(_ seconds: Double, _ source: String = "BRIO") -> RecordingEvent {
            RecordingEvent(at: Int64((seconds * 1e9).rounded()), event: .audioInputGap, audioSource: source)
        }
        let noAudio = RecordingEvent(at: 40_900_000_000, event: .noAudioStarted, audioSource: "BRIO")
        let events = [gap(5), gap(25.7), gap(27), gap(30.5, "Razer"), noAudio]
        #expect(ProblemsTold.gapsBefore(noAudio, in: events) == 25.7)
        #expect(ProblemsTold.gapsBefore(noAudio, in: [gap(20.8), noAudio]) == nil)
        #expect(ProblemsTold.gapsBefore(noAudio, in: [gap(20.9), noAudio]) == 20.9)
        #expect(ProblemsTold.gapsBefore(noAudio, in: [noAudio, gap(41)]) == nil)
    }

    // Calls to action (D84): only a problem a person has to do something about bounces the Dock, sets the
    // badge and counts.

    @Test func eachKindHasItsCallToActionOrNone() {
        #expect(ProblemKind.diskFull.callToAction == .freeUpDiskSpace)
        #expect(ProblemKind.manifestNotWritten.callToAction == .freeUpDiskSpace)
        // The timeline file is rewritten from the manifest by `msr timeline`: nothing is lost.
        #expect(ProblemKind.timelineFileNotWritten.callToAction == nil)
        #expect(ProblemKind.recordingLogNotWritten.callToAction == .freeUpDiskSpace)
        #expect(ProblemKind.cameraPermissionMissing.callToAction == .grantThePermission)
        #expect(ProblemKind.audioInputSilentAfterGaps("u").callToAction == .unplugAndPlugInAgain)
        #expect(ProblemKind.audioFileLost("a.mov").callToAction == .reportIt)
        #expect(ProblemKind.videoFileLost("v.mov").callToAction == .reportIt)
        let failing: [ProblemKind] = [
            .screenNotCaptured("U"), .cameraNotCaptured("C"), .audioSourceFailed("Mic"), .audioFileFailed("a.mov"),
            .audioInputNotRecordable("Mic"),
        ]
        for kind in failing + [.audioInputChangesNotFollowed] { #expect(kind.callToAction == .startAgainAndReportIt) }
        let none: [ProblemKind] = [
            .cameraStalled("C"), .guideTracksCut("v.mov"), .dockIconNotShown,
            .inputVolumeNotSet("Mic"), .inputVolumeNotFollowed("Mic"), .screensNotRead, .audioInputsNotRead, .freeSpaceNotRead,
        ]
        for kind in none { #expect(kind.callToAction == nil) }
        #expect(CallToAction.reportIt.includesReportIt && CallToAction.startAgainAndReportIt.includesReportIt)
        #expect(![CallToAction.freeUpDiskSpace, .grantThePermission, .unplugAndPlugInAgain].contains { $0.includesReportIt })
    }

    /// A kind with a call to action gives it once, at once; one without stays quiet.
    @Test func aCallToActionIsGivenOnceAtOnceAndNoneForAProblemWithout() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(1 * second, "Camera stalled"), kind: .cameraStalled("C"), to: &manifest)
        _ = told.add(problem(2 * second, "Cannot write the recording log"), kind: .recordingLogNotWritten, to: &manifest)
        #expect(told.callsToAction(now: 2 * second).map(\.problem) == ["Cannot write the recording log"])
        #expect(told.callsToAction(now: 3 * second).isEmpty)
        #expect(!told.asksToReportIt)
    }

    /// A source that fails and does not come back: its call to action once it lasted `unrecoveredAfter`; one that
    /// ends before stays quiet (D84).
    @Test func aFailingSourceCallsToActionOnlyOnceItLastedUnrecovered() {
        var told = ProblemsTold()
        var manifest = manifest()
        let after = RecorderValues.unrecoveredAfter.nanoseconds
        _ = told.add(problem(1 * second, "Screen 1 LG"), kind: .screenNotCaptured("U"), to: &manifest)
        _ = told.add(problem(2 * second, "Camera FaceTime"), kind: .cameraNotCaptured("C"), to: &manifest)
        #expect(told.callsToAction(now: 2 * second).isEmpty)
        #expect(told.nextCallToAction() == 1 * second + after)
        told.cleared(.cameraNotCaptured("C"), at: 5 * second)
        #expect(told.callsToAction(now: 1 * second + after - 1).isEmpty)
        #expect(!told.asksToReportIt)
        #expect(told.callsToAction(now: 1 * second + after).map(\.problem) == ["Screen 1 LG"])
        #expect(told.nextCallToAction() == nil)
        #expect(told.callsToAction(now: 100 * second).isEmpty)
        #expect(told.asksToReportIt)
    }

    /// A failure told after a newer file of its source started is over when told: no call to action.
    @Test func aFailureOverWhenToldCallsToNoAction() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(1 * second, "Audio file a.mov"), kind: .audioFileFailed("a.mov"), endedAt: 2 * second, to: &manifest)
        #expect(told.callsToAction(now: 100 * second).isEmpty)
        #expect(told.nextCallToAction() == nil)
    }

    /// A shown problem, such as an incomplete video file, gives its call to action too; only one whose words
    /// include "report it" asks for a report after the recording.
    @Test func onlyACallToActionWithReportItAsksForAReport() {
        var permission = ProblemsTold()
        var manifest = manifest()
        _ = permission.add(problem(1 * second, "The Camera permission"), kind: .cameraPermissionMissing, to: &manifest)
        _ = permission.add(problem(1 * second, "Silence"), kind: .audioInputSilentAfterGaps("u"), to: &manifest)
        permission.show(problem(1 * second, "Disk full"), kind: .diskFull)
        #expect(permission.callsToAction(now: 1 * second).count == 3)
        #expect(!permission.asksToReportIt)
        var lost = ProblemsTold()
        lost.show(problem(1 * second, "Screen file s.mov"), kind: .videoFileLost("s.mov"))
        #expect(lost.callsToAction(now: 1 * second).map(\.problem) == ["Screen file s.mov"])
        #expect(lost.asksToReportIt)
        var changes = ProblemsTold()
        _ = changes.add(problem(0, "Changes of the audio inputs"), kind: .audioInputChangesNotFollowed, to: &manifest)
        #expect(changes.callsToAction(now: 0).count == 1)
        #expect(changes.asksToReportIt)
    }

    /// A screen whose file ended because it showed another screen's picture: in the owner's table under none, so
    /// its problem never calls to action, also past `unrecoveredAfter`, shown first or told first (D84).
    @Test func aScreenShowingAnotherScreensPictureNeverCallsToAction() {
        var told = ProblemsTold()
        var manifest = manifest()
        told.show(problem(1 * second, "Screen file s.mov"), kind: .screenNotCaptured("U"), withoutCallToAction: true)
        _ = told.add(problem(1 * second, "Screen 1 LG"), kind: .screenNotCaptured("U"), withoutCallToAction: true, to: &manifest)
        _ = told.add(problem(1 * second, "Screen 2 DELL"), kind: .screenNotCaptured("V"), withoutCallToAction: true, to: &manifest)
        #expect(told.nextCallToAction() == nil)
        #expect(told.callsToAction(now: 100 * second).isEmpty)
        #expect(!told.asksToReportIt)
    }

    /// A failing source whose wait was over is called to action even when it ended before the call ran; at Stop,
    /// one still failing is called at once (D84).
    @Test func aCallDueIsNeverDroppedAndStopCallsTheOngoing() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(1 * second, "Mic"), kind: .audioSourceFailed("Mic"), to: &manifest)
        _ = told.add(problem(2 * second, "Cam"), kind: .cameraNotCaptured("C"), to: &manifest)
        _ = told.add(problem(3 * second, "Short"), kind: .screenNotCaptured("U"), to: &manifest)
        told.cleared(.audioSourceFailed("Mic"), at: 12 * second)
        told.cleared(.screenNotCaptured("U"), at: 4 * second)
        #expect(told.callsToAction(now: 12 * second).map(\.problem) == ["Mic", "Cam"])
        _ = told.add(problem(20 * second, "Mic again"), kind: .audioSourceFailed("Mic"), to: &manifest)
        #expect(told.callsToAction(now: 21 * second).isEmpty)
        #expect(told.callsToAction(now: 21 * second, atStop: true).map(\.problem) == ["Mic again"])
    }

    /// The screen's capture failing for another reason after its file showed another screen's picture is a
    /// failure like any other: it calls to action once unrecovered for the wait, counted from its tell.
    @Test func aFailureToldAfterAnotherScreensPictureCallsToAction() {
        var told = ProblemsTold()
        var manifest = manifest()
        told.show(problem(1 * second, "Screen file s.mov"), kind: .screenNotCaptured("U"), withoutCallToAction: true)
        _ = told.add(problem(5 * second, "Screen 1 LG"), kind: .screenNotCaptured("U"), to: &manifest)
        #expect(told.nextCallToAction() == 15 * second)
        #expect(told.callsToAction(now: 14 * second).isEmpty)
        #expect(told.callsToAction(now: 15 * second).map(\.problem) == ["Screen 1 LG"])
        #expect(told.asksToReportIt)
    }
    /// As the Recorder does it: another screen's picture told with the flag, then a failure of its own told.
    @Test func aFailureToldAfterAnotherScreensPictureToldCallsToAction() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(1 * second, "Screen 1 LG"), kind: .screenNotCaptured("U"), withoutCallToAction: true, to: &manifest)
        #expect(told.add(problem(3 * second, "Screen 1 LG again"), kind: .screenNotCaptured("U"), withoutCallToAction: true, to: &manifest)
            == .alreadyTold)
        #expect(told.add(problem(5 * second, "Screen 1 LG failed"), kind: .screenNotCaptured("U"), to: &manifest)
            == .tell(writeManifest: true))
        #expect(told.add(problem(6 * second, "Screen 1 LG failed again"), kind: .screenNotCaptured("U"), to: &manifest) == .alreadyTold)
        #expect(manifest.problems.map(\.problem) == ["Screen 1 LG", "Screen 1 LG failed"])
        #expect(told.nextCallToAction() == 15 * second)
        #expect(told.callsToAction(now: 15 * second).map(\.problem) == ["Screen 1 LG failed"])
    }

    /// The badge and the count show a call to action only while its problem lasts: once it ended, nothing is left
    /// to do (D84).
    @Test func aCallToActionCountsOnlyWhileItsProblemLasts() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(1 * second, "Disk full"), kind: .diskFull, to: &manifest)
        _ = told.add(problem(2 * second, "Mic"), kind: .audioSourceFailed("Mic"), to: &manifest)
        _ = told.callsToAction(now: 15 * second)
        #expect(told.callsToActionOngoing.map(\.problem) == ["Disk full", "Mic"])
        told.cleared(.diskFull, at: 20 * second)
        #expect(told.callsToActionOngoing.map(\.problem) == ["Mic"])
        told.cleared(.audioSourceFailed("Mic"), at: 21 * second)
        #expect(told.callsToActionOngoing.isEmpty)
    }
}
