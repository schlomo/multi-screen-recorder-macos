import Testing
@testable import EndToEndLogic

/// Lines copied from the owner's recording logs (`R1` 2026-11-25 13.23.54, `R2` 2026-11-24 06.30.02); the
/// ones marked synthetic are written from the format of the recorder's lines, where no real log has them.
@Suite struct AudioRowsFinalTests {
    // R1: the built-in microphone, the anchor, and the system audio; a Logitech BRIO comes later.
    static let micStartInput = #"13:23:54 +0.0s detail recorder: audio: startInput(uid: "BuiltInMicrophoneDevice", number: 1, name: "MacBook Pro Microphone")"#
    static let systemStart = "13:23:54 +0.0s detail recorder: audio: startSystemAudio"
    static let micStarted = "13:23:54 +0.2s detail recorder: file started: 2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov"
    static let micJoins = "13:23:54 +0.2s detail recorder: 2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov: joins the guide track placed earlier by 0 ms (the mix's zero: 2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov)"
    static let systemStarted = "13:23:54 +0.5s detail recorder: file started: 2026-11-25 13.23.54 Audio 0 - System.mov"
    static let systemDriftNotYet = "13:24:05 +11.1s detail recorder: Audio 0 - System: clock drift not measured yet, corrected 0 ms so far"
    static let micDriftNotYet = "13:24:05 +11.1s detail recorder: Audio 1 - MacBook Pro Microphone: clock drift not measured yet, corrected 0 ms so far"
    static let systemDrift = "13:24:15 +21.2s detail recorder: Audio 0 - System: clock drift -1000.0 ppm, corrected +9.10 ms so far, 10.81 ms off"
    static let micDrift = "13:24:15 +21.2s detail recorder: Audio 1 - MacBook Pro Microphone: clock drift -8.1 ppm, corrected +0.16 ms so far, 0.02 ms off"
    static let brioStartInput = #"13:24:48 +54.3s detail recorder: audio: startInput(uid: "AppleUSBAudioEngine:Unknown Manufacturer:Logitech BRIO:37AE85F2:4", number: 2, name: "Logitech BRIO")"#
    static let brioStarted = "13:24:48 +54.7s detail recorder: file started: 2026-11-25 13.24.48 Audio 2 - Logitech BRIO.mov"
    static let brioDriftNotYet = "13:24:56 +62.1s detail recorder: Audio 2 - Logitech BRIO: clock drift not measured yet, corrected 0 ms so far"
    static let brioJoins = "13:25:04 +70.1s detail recorder: 2026-11-25 13.24.48 Audio 2 - Logitech BRIO.mov: joins the guide track placed earlier by 0 ms (the mix's zero: 2026-11-25 13.24.48 Audio 2 - Logitech BRIO.mov)"
    static let brioDrift = "13:25:16 +82.3s detail recorder: Audio 2 - Logitech BRIO: clock drift +4.1 ppm, corrected -0.09 ms so far, 0.01 ms off"
    static let brioEnded = "13:25:53 +119.4s detail recorder: file ended: 2026-11-25 13.24.48 Audio 2 - Logitech BRIO.mov, finalized"
    static let brio = "2026-11-25 13.24.48 Audio 2 - Logitech BRIO.mov"

    static let anchorFinal = [micStartInput, systemStart, micStarted, micJoins, systemStarted, systemDrift, micDrift]

    // R2: the CalDigit's file ends after a gap at +25.8 s and a second one starts; a BRIO goes into no audio.
    static let calDigitStartInput = #"06:30:02 +0.0s detail recorder: audio: startInput(uid: "AppleUSBAudioEngine:CalDigit, Inc.:CalDigit Thunderbolt 3 Audio:21200000:2", number: 1, name: "CalDigit Thunderbolt 3 Audio")"#
    static let calDigitStarted = "06:30:03 +1.1s detail recorder: file started: 2026-11-24 06.30.03 Audio 1 - CalDigit Thunderbolt 3 Audio.mov"
    /// Synthetic: R2 is older than these lines.
    static let calDigitJoins = "06:30:20 +18.0s detail recorder: 2026-11-24 06.30.03 Audio 1 - CalDigit Thunderbolt 3 Audio.mov: joins the guide track placed earlier by 12 ms (the mix's zero: 2026-11-25 13.23.54 Audio 5 - MacBook Pro Microphone.mov)"
    static let calDigitEnded = "06:30:28 +25.8s detail recorder: file ended: 2026-11-24 06.30.03 Audio 1 - CalDigit Thunderbolt 3 Audio.mov, finalized"
    static let calDigitStartedAgain = "06:30:28 +25.8s detail recorder: file started: 2026-11-24 06.30.27 Audio 1 - CalDigit Thunderbolt 3 Audio.mov"
    static let calDigitDrift = "06:30:28 +25.9s detail recorder: Audio 1 - CalDigit Thunderbolt 3 Audio: clock drift +46.5 ppm, corrected -0.68 ms so far, 0.19 ms off"
    static let calDigitGap = "06:30:27 +25.8s detail recorder: Audio 1 - CalDigit Thunderbolt 3 Audio: gap of 1216.0 ms, clock drift corrected -0.88 ms so far, -0.057 ms for the gap, lateness 1261.97 ms before, 46.00 ms after"
    static let calDigitAgain = "2026-11-24 06.30.27 Audio 1 - CalDigit Thunderbolt 3 Audio.mov"
    static let brio2StartInput = #"06:30:02 +0.0s detail recorder: audio: startInput(uid: "AppleUSBAudioEngine:Unknown Manufacturer:Logitech BRIO:A267841D:4", number: 4, name: "Logitech BRIO")"#
    static let brio2Started = "06:30:03 +1.1s detail recorder: file started: 2026-11-24 06.30.03 Audio 4 - Logitech BRIO.mov"
    static let brio2DriftNotYet = "06:30:14 +11.9s detail recorder: Audio 4 - Logitech BRIO: clock drift not measured yet, corrected 0 ms so far"
    static let brio2NoAudio = "06:30:41 +38.8s no audio started: Logitech BRIO"
    /// Synthetic: no log has the event yet.
    static let brio2SoundAgain = "06:30:50 +47.8s no audio stopped: Logitech BRIO"
    static let brio2 = "2026-11-24 06.30.03 Audio 4 - Logitech BRIO.mov"

    func notFinal(_ lines: [String]) -> [String] { AudioRowsFinal.filesNotFinal(log: lines.joined(separator: "\n")) }

    @Test func theAnchorAndTheSystemAudioWaitForTheirClockDrift() {
        let early = [Self.micStartInput, Self.systemStart, Self.micStarted, Self.micJoins, Self.systemStarted,
                     Self.systemDriftNotYet, Self.micDriftNotYet]
        #expect(notFinal(early) == ["2026-11-25 13.23.54 Audio 0 - System.mov", "2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov"])
        #expect(notFinal(early + [Self.systemDrift]) == ["2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov"])
        #expect(notFinal(early + [Self.systemDrift, Self.micDrift]).isEmpty)
    }

    @Test func aLaterInputWaitsForItsJoinAndItsClockDrift() {
        let started = Self.anchorFinal + [Self.brioStartInput, Self.brioStarted, Self.brioDriftNotYet]
        #expect(notFinal(started) == [Self.brio])
        #expect(notFinal(started + [Self.brioJoins]) == [Self.brio])
        #expect(notFinal(started + [Self.brioDrift]) == [Self.brio])
        #expect(notFinal(started + [Self.brioJoins, Self.brioDrift]).isEmpty)
    }

    @Test func aFileEndedBeforeJoiningIsNotWaitedFor() {
        #expect(notFinal(Self.anchorFinal + [Self.brioStartInput, Self.brioStarted, Self.brioDriftNotYet, Self.brioEnded]).isEmpty)
    }

    @Test func aSourcesNewFileAfterAGapKeepsItsJoinAndAGapLineIsNoClockDrift() {
        // R2's own source 1, so none of R1's lines, whose numbers overlap.
        let first = [Self.calDigitStartInput, Self.calDigitStarted]
        let again = [Self.calDigitEnded, Self.calDigitStartedAgain, Self.calDigitGap]
        #expect(notFinal(first + again + [Self.calDigitDrift]) == [Self.calDigitAgain])
        #expect(notFinal(first + [Self.calDigitJoins] + again) == [Self.calDigitAgain])
        #expect(notFinal(first + [Self.calDigitJoins] + again + [Self.calDigitDrift]).isEmpty)
    }

    @Test func everyLineThatMakesTheSyncFinalCounts() {
        let started = Self.anchorFinal + [Self.brioStartInput, Self.brioStarted, Self.brioDrift]
        for ending in [
            "rejoins the guide track", "carries over 12 ms from 2026-11-25 13.20.00 Audio 2 - Logitech BRIO.mov",
            "in the guide track with the carried-over audio delay", "out of the guide track with the carried-over audio delay",
            "no clear sound to sync, 6 measurements with sound and no counted window",
            "leaves the guide track, +2.6 s from the staying group's earliest",
        ] {
            #expect(notFinal(started + ["13:25:04 +70.1s detail recorder: \(Self.brio): \(ending)"]).isEmpty, "\(ending)")
        }
        #expect(notFinal(started + ["13:25:04 +70.1s detail recorder: \(Self.brio): lag +3 ms dropped, not a device's newest file"]) == [Self.brio])
    }

    @Test func anInputInNoAudioIsNotWaitedForUntilItsSoundComesBack() {
        let silent = Self.anchorFinal + [Self.brio2StartInput, Self.brio2Started, Self.brio2DriftNotYet, Self.brio2NoAudio]
        #expect(notFinal(silent).isEmpty)
        #expect(notFinal(silent + [Self.brio2SoundAgain]) == [Self.brio2])
    }

    /// Synthetic: the file name has the name's `:` as `-` (`RecordingNames.fileNamePart`).
    @Test func aDeviceNameWithAColonIsFoundThroughItsNumber() {
        let lines = Self.anchorFinal + [
            #"13:24:48 +54.3s detail recorder: audio: startInput(uid: "USB-1", number: 2, name: "Desk: Mic")"#,
            "13:24:48 +54.7s detail recorder: file started: 2026-11-25 13.24.48 Audio 2 - Desk- Mic.mov",
            "13:24:56 +62.1s detail recorder: Audio 2 - Desk: Mic: clock drift +4.1 ppm, corrected -0.09 ms so far, 0.01 ms off",
        ]
        #expect(notFinal(lines) == ["2026-11-25 13.24.48 Audio 2 - Desk- Mic.mov"])
        #expect(notFinal(lines + ["13:25:01 +67.0s no audio started: Desk: Mic"]).isEmpty)
    }

    /// Synthetic: two devices of the same name are told apart by their numbers.
    @Test func twoDevicesOfTheSameNameAreToldApartByNumber() {
        let lines = Self.anchorFinal + [
            #"13:24:48 +54.3s detail recorder: audio: startInput(uid: "USB-1", number: 2, name: "USB Audio")"#,
            #"13:24:48 +54.3s detail recorder: audio: startInput(uid: "USB-2", number: 3, name: "USB Audio")"#,
            "13:24:48 +54.7s detail recorder: file started: 2026-11-25 13.24.48 Audio 2 - USB Audio.mov",
            "13:24:48 +54.7s detail recorder: file started: 2026-11-25 13.24.48 Audio 3 - USB Audio.mov",
            "13:25:04 +70.1s detail recorder: 2026-11-25 13.24.48 Audio 2 - USB Audio.mov: joins the guide track placed earlier by 0 ms (the mix's zero: 2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov)",
            "13:25:16 +82.3s detail recorder: Audio 2 - USB Audio: clock drift +4.1 ppm, corrected -0.09 ms so far, 0.01 ms off",
            "13:25:16 +82.3s detail recorder: Audio 3 - USB Audio: clock drift +4.1 ppm, corrected -0.09 ms so far, 0.01 ms off",
        ]
        #expect(notFinal(lines) == ["2026-11-25 13.24.48 Audio 3 - USB Audio.mov"])
    }

    /// Synthetic, from `AudioDelays`' format: a start-over shows every input "not synced yet" again, the new
    /// anchor excepted, until each joins again.
    @Test func aStartOverWaitsForEveryInputToJoinAgain() {
        let final = Self.anchorFinal + [Self.brioStartInput, Self.brioStarted, Self.brioJoins, Self.brioDrift]
        #expect(notFinal(final).isEmpty)
        let startOver = "13:25:20 +86.0s detail recorder: reference 2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov → \(Self.brio): "
            + "it has no audio delay, so it is the new anchor and every input starts over"
        let micJoinsAgain = "13:25:30 +96.0s detail recorder: 2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov: joins the guide track placed earlier by 0 ms (the mix's zero: \(Self.brio))"
        #expect(notFinal(final + [startOver]) == ["2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov"])
        #expect(notFinal(final + [startOver, micJoinsAgain]).isEmpty)
    }

    /// Synthetic, from `AudioDelays`' format (D89): a reference miss that moves the reference to a proven input
    /// starts over and waits for every input to show its sync again (a join, or its audio delay set when it was
    /// placed before), the old anchor that cannot sync ending at "no clear sound"; a re-base, as when the
    /// reference's capture ends, changes no row.
    @Test func aReferenceMovedOnAMissWaitsForTheStartOverAndARebaseChangesNothing() {
        let mic = "2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov"
        let final = Self.anchorFinal + [Self.brioStartInput, Self.brioStarted, Self.brioJoins, Self.brioDrift]
        let moves = "13:25:04 +70.1s detail recorder: reference \(mic): no counted window against it while another input "
            + "had sound; \(Self.brio) has counted windows of 1 other input against it: 2026-11-25 13.24.50 Audio 3 - Razer Seiren V3 Mini.mov"
        let startOver = "13:25:04 +70.1s detail recorder: reference \(mic) → \(Self.brio): moved on a reference miss, so it is the new "
            + "anchor and every input starts over"
        let noClearSound = "13:25:34 +100.1s detail recorder: \(mic): no clear sound to sync, 3 measurements with sound and no counted window"
        #expect(notFinal(final + [moves, startOver]) == [mic])
        #expect(notFinal(final + [moves, startOver, noClearSound]).isEmpty)
        let rebase = ["13:25:04 +70.1s detail recorder: reference \(mic) → \(Self.brio): lags re-based onto the anchor by 14 ms early"]
        #expect(notFinal(final + rebase).isEmpty)
    }

    /// Synthetic, from `AudioDelays`' format (D89): an input already in the guide track that syncs in the very
    /// measurement whose reference miss moves the reference logs only its audio delay being set, no join, as its
    /// placement may not change; that shows its sync.
    @Test func anInputPlacedBeforeAMissMoveShowsItsSyncWhenItsAudioDelayIsSet() {
        let mic = "2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov"
        let razer = "2026-11-25 13.24.48 Audio 3 - Razer Seiren V3 Mini.mov"
        let final = Self.anchorFinal + [Self.brioStartInput, Self.brioStarted, Self.brioJoins, Self.brioDrift,
            #"13:24:48 +54.3s detail recorder: audio: startInput(uid: "RAZER", number: 3, name: "Razer Seiren V3 Mini")"#,
            "13:24:48 +54.7s detail recorder: file started: \(razer)",
            "13:25:04 +70.1s detail recorder: \(razer): joins the guide track placed earlier by 0 ms (the mix's zero: \(Self.brio))",
            "13:25:16 +82.3s detail recorder: Audio 3 - Razer Seiren V3 Mini: clock drift +2.0 ppm, corrected -0.01 ms so far, 0.01 ms off"]
        #expect(notFinal(final).isEmpty)
        let moved = [
            "13:25:14 +80.1s detail recorder: reference \(mic): no counted window against it while another input had sound; "
                + "\(Self.brio) has counted windows of 1 other input against it: \(razer)",
            "13:25:14 +80.1s detail recorder: reference \(mic) → \(Self.brio): moved on a reference miss, so it is the new anchor "
                + "and every input starts over",
            "13:25:14 +80.1s detail recorder: \(razer): audio delay set by its first counted window: 14 ms late",
        ]
        #expect(notFinal(final + moved) == [mic])
    }

    /// Synthetic: no log has the system audio in no audio yet; its event names it "System audio".
    @Test func theSystemAudioInNoAudioIsNotWaitedFor() {
        let early = [Self.micStartInput, Self.systemStart, Self.micStarted, Self.micJoins, Self.systemStarted, Self.systemDriftNotYet, Self.micDrift]
        #expect(notFinal(early) == ["2026-11-25 13.23.54 Audio 0 - System.mov"])
        #expect(notFinal(early + ["13:24:05 +11.0s no audio started: System audio"]).isEmpty)
    }

    /// Synthetic: the label's number is the first " Audio N - " of the file name.
    @Test func aDeviceNameContainingAnAudioLabelKeepsItsOwnNumber() {
        let file = "2026-11-25 13.24.48 Audio 2 - Rack Audio 7 - Out.mov"
        let lines = Self.anchorFinal + [
            #"13:24:48 +54.3s detail recorder: audio: startInput(uid: "RACK", number: 2, name: "Rack Audio 7 - Out")"#,
            "13:24:48 +54.7s detail recorder: file started: \(file)",
            "13:25:04 +70.1s detail recorder: \(file): joins the guide track placed earlier by 0 ms (the mix's zero: \(file))",
            "13:25:16 +82.3s detail recorder: Audio 2 - Rack Audio 7 - Out: clock drift not measured yet, corrected 0 ms so far",
        ]
        #expect(notFinal(lines) == [file])
        #expect(notFinal(lines + ["13:25:26 +92.4s detail recorder: Audio 2 - Rack Audio 7 - Out: clock drift +4.0 ppm, corrected -0.11 ms so far, 0.01 ms off"]).isEmpty)
        #expect(notFinal(lines + ["13:25:20 +86.0s detail recorder: file ended: \(file), finalized"]).isEmpty)
    }

    @Test func noLogYetMeansNoAudioRowToWaitFor() {
        #expect(notFinal([]).isEmpty)
    }
}
