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

    // The status window's lines (D78, D91): only a problem whose call to action was given shows a line.

    private let second: Int64 = 1_000_000_000

    private func nanoseconds(_ seconds: Double) -> Int64 { Int64((seconds * 1_000_000_000).rounded()) }

    /// Told, then its call to action given if it has one now, as the Recorder does.
    private func tell(
        _ told: inout ProblemsTold, _ manifest: inout RecordingManifest, _ problem: RecordingProblem, kind: ProblemKind,
        source: String? = nil, note: String? = nil
    ) {
        _ = told.add(problem, kind: kind, source: source, note: note, to: &manifest)
        _ = told.callsToAction(now: Int64((problem.at * 1_000_000_000).rounded()))
    }

    /// The owner's rule (D91): a problem without a call to action shows nothing, though it is told and listed.
    @Test(arguments: [
        (ProblemKind.cameraPermissionMissing, true), (.diskFull, true), (.recordingLogNotWritten, true), (.manifestNotWritten, true),
        (.audioInputSilentAfterGaps("A"), true), (.audioFileLost("f"), true), (.videoFileLost("f"), true),
        (.audioInputChangesNotFollowed, true), (.screenNotCaptured("S"), true), (.cameraNotCaptured("C"), true),
        (.audioSourceFailed("A"), true), (.audioFileFailed("f"), true), (.audioInputNotRecordable("A"), true),
        (.cameraStalled("C"), false), (.dockIconNotShown, false), (.inputVolumeNotSet("A"), false),
        (.inputVolumeNotFollowed("A"), false), (.timelineFileNotWritten, false), (.guideTracksCut("f"), false),
        (.freeSpaceNotRead, false), (.screensNotRead, false), (.audioInputsNotRead, false),
    ])
    func onlyAProblemWithACallToActionShowsALine(kind: ProblemKind, shows: Bool) {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(second), kind: kind, to: &manifest)
        _ = told.callsToAction(now: 2 * second, unrecoveredAfter: .seconds(1))
        #expect(told.lines(now: 2 * second).isEmpty == !shows)
        #expect(manifest.problems.count == 1)
    }

    /// A failing source shows its line only once its call to action is given, after `unrecoveredAfter`; one that
    /// came back before stays without a line, and so do its short repeats (D84, D91).
    @Test func aFailingSourceShowsItsLineOnlyOnceUnrecovered() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(1 * second), kind: .screenNotCaptured("U"), source: "DELL", to: &manifest)
        _ = told.callsToAction(now: 5 * second)
        #expect(told.lines(now: 5 * second).isEmpty)
        _ = told.callsToAction(now: 11 * second)
        #expect(told.lines(now: 11 * second) == ["Screen DELL not captured since 0:01: denied"])
        told.cleared(.screenNotCaptured("U"), at: 16 * second)
        _ = told.add(problem(20 * second), kind: .screenNotCaptured("U"), source: "DELL", to: &manifest)
        told.cleared(.screenNotCaptured("U"), at: 23 * second)
        _ = told.callsToAction(now: 40 * second)
        #expect(told.lines(now: 40 * second) == ["Screen DELL not captured for 15 s at 0:01, recovered: denied"])
    }

    /// A source that keeps failing for under `unrecoveredAfter` each time: its failures add up, and once its
    /// lost time reaches `unrecoveredAfter` in total, its call to action is given once, for the failure then
    /// lasting (D91). The reviewer's probe: 50 failures of 8 s in 600 s.
    @Test func aSourceFailingAgainAndAgainCallsToActionOnceItsLostTimeAddsUp() {
        var told = ProblemsTold()
        var manifest = manifest()
        var calls: [RecordingProblem] = []
        for index in 0..<50 {
            let began = Int64(index) * 12 * second
            _ = told.add(problem(began, "Mic \(index)"), kind: .audioSourceFailed("Mic"), to: &manifest)
            calls += told.callsToAction(now: began)
            if index == 1 { #expect(told.nextCallToAction() == 14 * second) }
            if let due = told.nextCallToAction(), due < began + 8 * second { calls += told.callsToAction(now: due) }
            told.cleared(.audioSourceFailed("Mic"), at: began + 8 * second)
            calls += told.callsToAction(now: began + 8 * second)
        }
        #expect(calls.map(\.problem) == ["Mic 1"])
        #expect(told.gaveACallToAction && told.asksToReportIt)
        #expect(told.lines(now: 600 * second) == ["Mic not captured for 8.0 s at 0:12, recovered: denied"])
    }

    /// Lost time adds up per source: another source's failures do not count, nor a screen's file ended by
    /// another screen's picture, which calls to no action (D84, D91).
    @Test func lostTimeAddsUpPerSourceOnly() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(0), kind: .audioSourceFailed("A"), to: &manifest)
        told.cleared(.audioSourceFailed("A"), at: 6 * second)
        _ = told.add(problem(0, "Screen 1 LG"), kind: .screenNotCaptured("U"), withoutCallToAction: true, to: &manifest)
        told.cleared(.screenNotCaptured("U"), at: 20 * second)
        _ = told.add(problem(20 * second), kind: .audioSourceFailed("B"), to: &manifest)
        _ = told.add(problem(21 * second, "Screen 1 LG failed"), kind: .screenNotCaptured("U"), to: &manifest)
        #expect(told.callsToAction(now: 25 * second).isEmpty)
        #expect(told.nextCallToAction() == 30 * second)
    }

    /// Repeats of a kind share one line, with other kinds told between them.
    @Test func repeatsOfAKindShareOneLine() {
        var told = ProblemsTold()
        var manifest = manifest()
        tell(&told, &manifest, problem(10 * second), kind: .diskFull)
        told.cleared(.diskFull, at: 14 * second)
        tell(&told, &manifest, problem(20 * second), kind: .recordingLogNotWritten)
        tell(&told, &manifest, problem(30 * second), kind: .diskFull)
        told.cleared(.diskFull, at: 35 * second)
        tell(&told, &manifest, problem(40 * second), kind: .diskFull)
        #expect(told.lines(now: 43 * second) == [
            "Disk full 3 times, 12 s in total: denied", "Recording log not written since 0:20: denied",
        ])
        told.cleared(.diskFull, at: 41 * second)
        #expect(told.lines(now: 50 * second).first == "Disk full 3 times, 10 s in total, recovered: denied")
        #expect(manifest.problems.count == 4)
    }

    @Test func aProblemThatEndsTellsHowLongItLasted() {
        var told = ProblemsTold()
        var manifest = manifest()
        tell(&told, &manifest, problem(12 * second), kind: .recordingLogNotWritten)
        #expect(told.lines(now: 13 * second) == ["Recording log not written since 0:12: denied"])
        told.cleared(.recordingLogNotWritten, at: 16 * second)
        #expect(told.lines(now: 20 * second) == ["Recording log not written for 4.0 s at 0:12, recovered: denied"])
        tell(&told, &manifest, RecordingProblem(at: 3723 * second, problem: "x", error: "gone"), kind: .recordingLogNotWritten)
        #expect(told.lines(now: 3724 * second) == ["Recording log not written 2 times, 5.0 s in total: latest: gone"])
    }

    /// Each kind's own words; a kind keyed by an ID names its source as told.
    @Test func eachKindHasItsOwnPhrase() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(12 * second, "Screen DELL"), kind: .screenNotCaptured("U"), source: "DELL", to: &manifest)
        told.cleared(.screenNotCaptured("U"), at: 14 * second, ending: .disconnected)
        _ = told.add(problem(20 * second, "x"), kind: .audioInputNotRecordable("Razer"), to: &manifest)
        told.track(problem(21 * second, "y"), kind: .videoFileLost("Screen 1 - DELL.mov"))
        _ = told.callsToAction(now: 30 * second, unrecoveredAfter: .seconds(1))
        #expect(told.lines(now: 30 * second) == [
            "File Screen 1 - DELL.mov incomplete since 0:21: denied",
            "Audio input Razer not recordable since 0:20: denied",
            "Screen DELL not captured for 2.0 s at 0:12, then disconnected: denied",
        ])
    }

    /// A line only shown, as a video file's end, keeps no tell of its kind from the manifest; and only a
    /// failure that ends with a new file can be over when told: a full disk or a lost file never are.
    @Test func aShownLineNeitherSwallowsATellNorEndsWhatANewFileDoesNotEnd() {
        var told = ProblemsTold()
        var manifest = manifest()
        told.track(problem(5 * second, "Camera file c.mov"), kind: .cameraNotCaptured("C"), source: "BRIO")
        #expect(told.add(problem(5 * second, "Camera BRIO stream failed"), kind: .cameraNotCaptured("C"), source: "BRIO", to: &manifest)
            == .tell(writeManifest: true))
        #expect(manifest.problems.count == 1)
        #expect(told.add(problem(6 * second, "Camera BRIO"), kind: .cameraNotCaptured("C"), source: "BRIO", to: &manifest) == .alreadyTold)
        told.track(problem(5 * second, "g"), kind: .videoFileLost("Screen 1 - DELL.mov"), endedAt: 6 * second)
        told.track(problem(5 * second, "d"), kind: .diskFull, endedAt: 6 * second)
        _ = told.callsToAction(now: 7 * second, unrecoveredAfter: .seconds(1))
        #expect(told.lines(now: 7 * second) == [
            "Disk full since 0:05: denied", "File Screen 1 - DELL.mov incomplete since 0:05: denied",
            "Camera BRIO not captured since 0:05: denied",
        ])
    }

    /// Newest first, whatever the kind.
    @Test func linesComeNewestFirst() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(1 * second), kind: .screenNotCaptured("A"), source: "A", to: &manifest)
        _ = told.add(problem(2 * second), kind: .dockIconNotShown, to: &manifest)
        _ = told.add(problem(3 * second), kind: .screenNotCaptured("B"), source: "B", to: &manifest)
        _ = told.add(problem(4 * second), kind: .diskFull, to: &manifest)
        _ = told.callsToAction(now: 5 * second, unrecoveredAfter: .seconds(1))
        #expect(told.lines(now: 5 * second) == [
            "Disk full since 0:04: denied", "Screen B not captured since 0:03: denied", "Screen A not captured since 0:01: denied",
        ])
    }

    /// One decimal below 10 s (as rounded), whole seconds from there, m:ss from a minute on.
    @Test func lengthsAreShownAsTheyRound() {
        for (length, shown) in [(9.94, "9.9 s"), (9.96, "10 s"), (10.45, "10 s"), (59.6, "1:00"), (125.0, "2:05")] {
            var told = ProblemsTold()
            var manifest = manifest()
            tell(&told, &manifest, problem(0), kind: .diskFull)
            told.cleared(.diskFull, at: nanoseconds(length))
            #expect(told.lines(now: nanoseconds(length)).first == "Disk full for \(shown) at 0:00, recovered: denied")
        }
    }

    /// Following the audio inputs' changes failing is its own problem: a working read of them does not end it.
    @Test func changesOfTheAudioInputsNotFollowedIsNotEndedByAReadOfThem() {
        var told = ProblemsTold()
        var manifest = manifest()
        let notFollowed = RecordingProblem(atSeconds: 0, problem: "Changes of the audio inputs cannot be followed", error: "denied")
        tell(&told, &manifest, notFollowed, kind: .audioInputChangesNotFollowed)
        told.cleared(.audioInputsNotRead, at: 5 * second)
        #expect(told.add(problem(6 * second, "The audio inputs cannot be read"), kind: .audioInputsNotRead, to: &manifest)
            == .tell(writeManifest: true))
        #expect(told.lines(now: 7 * second) == ["Changes of the audio inputs not followed since 0:00: denied"])
    }

    /// An audio input silent right after its gaps: what to do while it lasts, in the past once its sound returns
    /// or it disconnects (D81).
    @Test func anAudioInputSilentAfterItsGapsSaysWhatToDoUntilItsSoundReturns() {
        var told = ProblemsTold()
        var manifest = manifest()
        let kind = ProblemKind.audioInputSilentAfterGaps("B")
        let silent = RecordingProblem(at: 31 * second, problem: "The audio input BRIO sends only silence after its gaps", error: nil)
        #expect(told.add(silent, kind: kind, source: "Audio 3 BRIO", note: "0:25", to: &manifest) == .tell(writeManifest: true))
        _ = told.callsToAction(now: 31 * second)
        #expect(told.lines(now: 45 * second) == ["Audio 3 BRIO sends only silence since its gaps at 0:25; unplug and plug it in again"])
        told.cleared(kind, at: 96 * second)
        #expect(told.lines(now: 100 * second) == ["Audio 3 BRIO sent only silence for 1:05 after its gaps at 0:25, recovered"])
        tell(&told, &manifest, silent, kind: kind, source: "Audio 3 BRIO", note: "0:25")
        told.cleared(kind, at: 40 * second, ending: .disconnected)
        #expect(told.lines(now: 100 * second).first == "Audio 3 BRIO sent only silence for 9.0 s after its gaps at 0:25, then disconnected")
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
        #expect(told.callsToAction(now: 1 * second).isEmpty)
        #expect(!told.gaveACallToAction)
        _ = told.add(problem(2 * second, "Cannot write the recording log"), kind: .recordingLogNotWritten, to: &manifest)
        #expect(told.callsToAction(now: 2 * second).map(\.problem) == ["Cannot write the recording log"])
        #expect(told.gaveACallToAction)
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

    /// A failure told after a newer file of its source started is over when told: no call to action, no line.
    @Test func aFailureOverWhenToldCallsToNoAction() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(1 * second, "Audio file a.mov"), kind: .audioFileFailed("a.mov"), endedAt: 2 * second, to: &manifest)
        #expect(told.callsToAction(now: 100 * second).isEmpty)
        #expect(told.nextCallToAction() == nil)
        #expect(told.lines(now: 100 * second).isEmpty)
    }

    /// A shown problem, such as an incomplete video file, gives its call to action too; only one whose words
    /// include "report it" asks for a report after the recording.
    @Test func onlyACallToActionWithReportItAsksForAReport() {
        var permission = ProblemsTold()
        var manifest = manifest()
        _ = permission.add(problem(1 * second, "The Camera permission"), kind: .cameraPermissionMissing, to: &manifest)
        _ = permission.add(problem(1 * second, "Silence"), kind: .audioInputSilentAfterGaps("u"), to: &manifest)
        permission.track(problem(1 * second, "Disk full"), kind: .diskFull)
        #expect(permission.callsToAction(now: 1 * second).count == 3)
        #expect(!permission.asksToReportIt)
        var lost = ProblemsTold()
        lost.track(problem(1 * second, "Screen file s.mov"), kind: .videoFileLost("s.mov"))
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
        told.track(problem(1 * second, "Screen file s.mov"), kind: .screenNotCaptured("U"), withoutCallToAction: true)
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
        told.track(problem(1 * second, "Screen file s.mov"), kind: .screenNotCaptured("U"), withoutCallToAction: true)
        _ = told.add(problem(5 * second, "Screen 1 LG"), kind: .screenNotCaptured("U"), to: &manifest)
        #expect(told.nextCallToAction() == 15 * second)
        #expect(told.callsToAction(now: 14 * second).isEmpty)
        #expect(told.callsToAction(now: 15 * second).map(\.problem) == ["Screen 1 LG"])
        #expect(told.asksToReportIt)
    }
    /// The problems whose call to action was given, for `msr record`'s summary: never one told without it, nor
    /// one a later tell replaced, as another screen's picture followed by that screen's failure within the wait (D91).
    @Test func everyProblemCalledToActionListsOnlyThose() {
        var told = ProblemsTold()
        var manifest = manifest()
        _ = told.add(problem(1 * second, "Screen 1 LG"), kind: .screenNotCaptured("U"), withoutCallToAction: true, to: &manifest)
        _ = told.add(problem(5 * second, "Screen 1 LG failed"), kind: .screenNotCaptured("U"), to: &manifest)
        _ = told.add(problem(6 * second, "Camera stalled"), kind: .cameraStalled("C"), to: &manifest)
        told.cleared(.screenNotCaptured("U"), at: 8 * second)
        #expect(told.callsToAction(now: 8 * second).isEmpty)
        #expect(told.everyProblemCalledToAction.isEmpty)
        #expect(manifest.problems.count == 3)
        _ = told.add(problem(9 * second, "Disk full"), kind: .diskFull, to: &manifest)
        _ = told.callsToAction(now: 9 * second)
        #expect(told.everyProblemCalledToAction.map(\.problem) == ["Disk full"])
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
