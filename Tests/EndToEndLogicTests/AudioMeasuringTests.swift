import Testing
@testable import EndToEndLogic

/// Lines copied from the owner's recording.log of 2026-11-25 13.23.54; the "no clear sound" line,
/// which that log lacks, is written from `AudioDelays`' format.
@Suite struct AudioMeasuringTests {
    static let anchorStarted = "13:23:54 +0.2s detail recorder: file started: 2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov"
    static let anchorJoins = "13:23:54 +0.2s detail recorder: 2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov: joins the guide track placed earlier by 0 ms (the mix's zero: 2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov)"
    static let screenStarted = "13:23:54 +0.4s detail recorder: file started: 2026-11-25 13.23.54 Screen 1 - Built-in Retina Display.mov"
    static let systemStarted = "13:23:54 +0.5s detail recorder: file started: 2026-11-25 13.23.54 Audio 0 - System.mov"
    static let brioStarted = "13:24:48 +54.7s detail recorder: file started: 2026-11-25 13.24.48 Audio 2 - Logitech BRIO.mov"
    static let brioNotMeasured = "13:24:54 +60.1s detail recorder: 2026-11-25 13.24.48 Audio 2 - Logitech BRIO.mov: not measured, it or the reference 2026-11-25 13.23.54 Audio 1 - MacBook Pro Microphone.mov has less than a window of sound"
    static let brioJoins = "13:25:04 +70.1s detail recorder: 2026-11-25 13.24.48 Audio 2 - Logitech BRIO.mov: joins the guide track placed earlier by 0 ms (the mix's zero: 2026-11-25 13.24.48 Audio 2 - Logitech BRIO.mov)"
    static let brioUnclear = "13:25:04 +70.1s detail recorder: 2026-11-25 13.24.48 Audio 2 - Logitech BRIO.mov: no clear sound to sync, 6 measurements with sound and no counted window"
    static let brio = "2026-11-25 13.24.48 Audio 2 - Logitech BRIO.mov"

    func measuring(_ lines: [String]) -> [String] { AudioMeasuring.filesMeasuring(log: lines.joined(separator: "\n")) }

    @Test func theAnchorsFileIsJoinedFromItsStartAndScreensAndTheSystemAudioAreNotMeasured() {
        #expect(measuring([Self.anchorStarted, Self.anchorJoins, Self.screenStarted, Self.systemStarted]).isEmpty)
    }

    @Test func anInputFileIsMeasuringUntilItJoinsTheGuideTrack() {
        let started = [Self.anchorStarted, Self.anchorJoins, Self.systemStarted, Self.brioStarted, Self.brioNotMeasured]
        #expect(measuring(started) == [Self.brio])
        #expect(measuring(started + [Self.brioJoins]).isEmpty)
    }

    @Test func anInputFileWithNoClearSoundToSyncIsOutOfMeasuring() {
        #expect(measuring([Self.anchorStarted, Self.anchorJoins, Self.brioStarted, Self.brioUnclear]).isEmpty)
    }

    /// From the owner's recording.log of 2026-11-24 06.30.02; the "no audio stopped" line, which no log has yet,
    /// is written from the event's name.
    static let silentStarted = "06:30:03 +1.1s detail recorder: file started: 2026-11-24 06.30.03 Audio 4 - Logitech BRIO.mov"
    static let otherNoAudio = "06:30:12 +10.2s no audio started: MacBook Pro Microphone"
    static let silentNoAudio = "06:30:41 +38.8s no audio started: Logitech BRIO"
    static let silentSoundAgain = "06:30:50 +47.8s no audio stopped: Logitech BRIO"
    static let silent = "2026-11-24 06.30.03 Audio 4 - Logitech BRIO.mov"

    @Test func anInputFileInNoAudioIsOutOfMeasuringUntilItsSoundComesBack() {
        #expect(measuring([Self.anchorStarted, Self.anchorJoins, Self.silentStarted, Self.otherNoAudio]) == [Self.silent])
        let silent = [Self.anchorStarted, Self.anchorJoins, Self.silentStarted, Self.silentNoAudio]
        #expect(measuring(silent).isEmpty)
        #expect(measuring(silent + [Self.silentSoundAgain]) == [Self.silent])
    }

    @Test func noLogYetMeansNothingKnownToMeasure() {
        #expect(measuring([]).isEmpty)
    }
}
