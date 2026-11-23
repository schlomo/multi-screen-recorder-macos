import RecorderLogic
import Testing
@testable import RecorderCore

@Suite struct AudioDelayFeedTests {
    private static let rate = Int64(RecorderValues.audioSampleRate)

    private static func nanoseconds(ofSample sample: Int64) -> Int64 { sample * 1_000_000_000 / rate }

    @Test func buffersInARowLandOnTheTimelineAtTheMeasuringRate() throws {
        let feed = AudioDelayFeed()
        feed.receive([[Float](repeating: 1, count: 1000)], from: "R", at: Self.nanoseconds(ofSample: 4800))
        feed.receive([[Float](repeating: 0.5, count: 1000)], from: "R", at: Self.nanoseconds(ofSample: 5800))
        #expect(feed.endIndex(of: "R") == 1133)
        let window = try #require(feed.window(of: "R", endingAt: 1133, count: 333))
        #expect(window.first == 1)
        #expect(window.last == 0.5)
        #expect(feed.window(of: "R", endingAt: 1133, count: 334) == nil)
        #expect(feed.window(of: "other", endingAt: 1133, count: 1) == nil)
    }

    @Test func aGapIsSilenceAndOnlyTheLatestSecondsAreKept() throws {
        let feed = AudioDelayFeed()
        feed.receive([[Float](repeating: 1, count: 600)], from: "R", at: 0)
        feed.receive([[Float](repeating: 1, count: 600)], from: "R", at: Self.nanoseconds(ofSample: 1200))
        let window = try #require(feed.window(of: "R", endingAt: 300, count: 300))
        #expect(window[0..<100].allSatisfy { $0 == 1 })
        #expect(window[100..<200].allSatisfy { $0 == 0 })
        #expect(window[200..<300].allSatisfy { $0 == 1 })
        let kept = AudioDelayFeed.keptSeconds * AudioDelay.sampleRate
        let long = [[Float](repeating: 0.25, count: 3 * kept * AudioDelay.decimation)]
        feed.receive(long, from: "R", at: Self.nanoseconds(ofSample: 1800))
        let end = try #require(feed.endIndex(of: "R"))
        #expect(feed.window(of: "R", endingAt: end, count: kept) != nil)
        #expect(feed.window(of: "R", endingAt: end, count: 2 * kept + 1) == nil)
    }
}
