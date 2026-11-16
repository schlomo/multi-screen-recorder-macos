import Foundation
import RecorderLogic
import Testing
@testable import RecorderCore

/// The guide tracks' end at Stop: the last mix waits for audio up to the
/// video's end, bounded by `audioWaitBoundSeconds`.
@Suite struct GuideTrackFeedTests {
    private let rate = Int64(RecorderValues.audioSampleRate)

    private func feed() -> GuideTrackFeed {
        let feed = GuideTrackFeed(tracks: [.microphones], now: { 0 })
        feed.add(source: "Razer", channelCount: 1, to: .microphones)
        return feed
    }

    @Test func theLastMixWaitsForSamplesThatComeLate() async {
        let feed = feed()
        // The source's sound runs from time 0 for one second: sample positions 0 up to `rate`.
        let end = rate
        feed.receive([[Float](repeating: 0.25, count: Int(rate / 2))], from: "Razer", to: .microphones, at: 0)
        let late = Task {
            try? await Task.sleep(for: .milliseconds(150))
            feed.receive([[Float](repeating: 0.25, count: Int(rate / 2))], from: "Razer", to: .microphones,
                         at: 500_000_000)
        }
        // A bound far beyond the delay: a busy machine may run the late
        // delivery much later than 150 ms, and only the outcome counts.
        let received = await feed.waitUntilReceived(upTo: end, bound: .seconds(60))
        #expect(received)
        // Peeked right away: a wait that returned before the late samples
        // came would leave silence at the end.
        let id = feed.listen { _, _, _ in }
        let peek = feed.stopListening(id, peekingUpTo: end)[.microphones]
        #expect(peek.map { $0.channels.first?.count == Int(end - $0.start) } == true)
        #expect(peek?.channels.first?.last == 0.25)
        late.cancel()
    }

    @Test func withoutTheSamplesTheWaitEndsAtItsBound() async {
        let feed = feed()
        let end = rate
        let clock = SuspendingClock()
        let began = clock.now
        let received = await feed.waitUntilReceived(upTo: end, bound: .milliseconds(100))
        #expect(!received)
        #expect(clock.now - began >= .milliseconds(100))
    }
}
