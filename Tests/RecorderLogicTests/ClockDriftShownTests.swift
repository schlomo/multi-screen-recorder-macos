import Testing
@testable import RecorderLogic

/// Which audio sources show a clock drift status, in the window and in the `--debug` block.
@Suite struct ClockDriftShownTests {
    private func source(_ id: AudioTracker.SourceID, _ number: Int) -> AudioTracker.Source {
        .init(id: id, number: number, name: "N\(number)", state: .recording)
    }

    private func status(_ applied: Double) -> ClockDriftCorrection.Status {
        .init(clockDriftPpm: 1, applied: applied, remaining: 0)
    }

    private let shown = [AudioTracker.SourceID.input("B"), .systemAudio, .input("A")].enumerated().map { offset, id in
        AudioTracker.Source(id: id, number: [2, 0, 1][offset], name: "N", state: .recording)
    }

    @Test func aRunningSourceWithAReportIsInAndTheOrderIsByNumber() {
        let result = ClockDriftShown.sources(
            shown: shown,
            reports: [.input("B"): (number: 7, status: status(2)), .systemAudio: (number: 5, status: status(0)),
                      .input("A"): (number: 6, status: status(1))],
            running: [.input("B"): 7, .systemAudio: 5, .input("A"): 6])
        #expect(result.map(\.source.number) == [0, 1, 2])
        #expect(result.map(\.status.applied) == [0, 1, 2])
    }

    @Test func aSourceWhoseCaptureEndedIsOut() {
        let result = ClockDriftShown.sources(
            shown: shown, reports: [.input("A"): (number: 6, status: status(1)), .input("B"): (number: 7, status: status(2))],
            running: [.input("B"): 7])
        #expect(result.map(\.source.id) == [.input("B")])
    }

    /// A reconnected source's new capture has another number than the one its report came from.
    @Test func aReconnectedSourceWhoseNewCaptureHasNotReportedYetIsOut() {
        let result = ClockDriftShown.sources(
            shown: shown, reports: [.input("A"): (number: 6, status: status(1))], running: [.input("A"): 8])
        #expect(result.isEmpty)
    }

    @Test func aRunningSourceWithoutAReportIsOut() {
        #expect(ClockDriftShown.sources(shown: shown, reports: [:], running: [.input("A"): 6]).isEmpty)
    }
}
