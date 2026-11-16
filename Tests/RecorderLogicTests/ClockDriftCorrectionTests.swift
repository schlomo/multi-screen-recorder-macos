import Foundation
import Testing
@testable import RecorderLogic

@Suite struct ClockDriftCorrectionTests {
    private let sampleRate = 48_000.0

    /// Clicks of a device 500 ppm slow at known shared clock times, with
    /// jittered arrivals: each comes out at its time once the correction
    /// has caught up.
    @Test func clicksComeOutAtTheirSharedClockTimes() throws {
        let device = SimulatedDevice.steady(ppm: -500)
        let seconds = 60.0
        let buffers = device.buffers(for: seconds)
        // A click at the shared clock time T is at the device's sample T · rate / (1 + 500 ppm).
        let clicks = stride(from: 0.75, to: seconds - 1, by: 1.0).map { $0 }
        var input = [Float](repeating: 0, count: buffers.count * SimulatedDevice.bufferSamples)
        for click in clicks { input[Int((click * sampleRate / (1 + 500e-6)).rounded())] = 1 }

        var correction = ClockDriftCorrection()
        var chunks: [ClockDriftCorrection.Chunk] = []
        for buffer in buffers {
            let start = buffer.index * SimulatedDevice.bufferSamples
            chunks += correction.correct([Array(input[start..<(start + SimulatedDevice.bufferSamples)])], at: buffer.time, arrival: buffer.arrival)
        }
        chunks += correction.flush()

        // Each click is the loudest output sample within 50 ms of its time.
        var loudest = [(seconds: Double, sample: Float)](repeating: (0, 0), count: clicks.count)
        for chunk in chunks {
            for (index, sample) in chunk.channels[0].enumerated() {
                let at = Double(chunk.time) / 1e9 + Double(index) / sampleRate
                let click = Int((at - clicks[0]).rounded())
                guard clicks.indices.contains(click), abs(at - clicks[click]) < 0.05, sample > loudest[click].sample else { continue }
                loudest[click] = (at, sample)
            }
        }
        for (click, found) in zip(clicks, loudest) {
            #expect(abs(found.seconds - click) < (click < 15 ? 0.002 : 0.0005), "the click at \(click) s came at \(found.seconds) s")
        }
        let status = correction.status
        #expect(abs(try #require(status.clockDriftPpm) - -500) < 2)
        #expect(abs(status.applied - 0.03) < 0.0005)
        #expect(abs(try #require(status.remaining)) < 0.0005)
    }

    @Test func aGapComesOutAsAJumpOfItsLengthWithNothingLostBefore() throws {
        let device = SimulatedDevice.steady(ppm: -500)
        let buffers = device.buffers(for: 6)
        let gap: Int64 = 100_000_000
        let gapAt = 300
        var correction = ClockDriftCorrection()
        var before: [ClockDriftCorrection.Chunk] = []
        var after: [ClockDriftCorrection.Chunk] = []
        let samples = [Float](repeating: 0.25, count: SimulatedDevice.bufferSamples)
        for buffer in buffers {
            let isAfter = buffer.index >= gapAt
            let chunks = correction.correct(
                [samples], at: buffer.time + (isAfter ? gap : 0), arrival: buffer.arrival + (isAfter ? gap : 0))
            if buffer.index == gapAt {
                // The tail of the segment before, then the first chunk after.
                before += chunks.dropLast()
                after += chunks.suffix(1)
            } else if isAfter {
                after += chunks
            } else {
                before += chunks
            }
        }
        let output = before.reduce(0) { $0 + $1.channels[0].count }
        let appliedAtGap = try #require(before.last).applied
        // Every sample before the gap came out: the input and the correction applied.
        let input = Double(gapAt * SimulatedDevice.bufferSamples)
        #expect(abs(Double(output) - input - appliedAtGap * sampleRate) <= 1)
        let end = Double(try #require(before.first).time) + Double(output) / sampleRate * 1e9
        let jump = Double(try #require(after.first).time) - end
        #expect(abs(jump - Double(gap)) <= 1e9 / sampleRate, "\(jump) ns")
        // Within a segment the chunks follow each other by sample count.
        for (chunk, next) in zip(before, before.dropFirst()) {
            #expect(abs(Double(next.time - chunk.time) - Double(chunk.channels[0].count) / sampleRate * 1e9) <= 1)
        }
    }

    @Test func aChannelCountChangeStartsANewSegment() {
        var correction = ClockDriftCorrection()
        let mono = [[Float](repeating: 0.25, count: 512)]
        let stereo = mono + mono
        var chunks = correction.correct(mono, at: 0, arrival: 20_000_000)
        chunks += correction.correct(mono, at: 10_666_666, arrival: 30_000_000)
        #expect(chunks.allSatisfy { $0.channels.count == 1 })
        let monoOut = chunks.reduce(0) { $0 + $1.channels[0].count }
        let changed = correction.correct(stereo, at: 21_333_333, arrival: 40_000_000)
        #expect(changed.map(\.channels.count) == [1, 2])
        #expect(monoOut + changed[0].channels[0].count == 1024)
        // The new segment starts at its own timestamp, the correction applied so far added.
        #expect(changed[1].time == 21_333_333)
        #expect(changed[1].channels[0].count == 512 - RecorderValues.clockDriftResamplerTaps / 2)
    }

    @Test func noBufferNoChunk() {
        var correction = ClockDriftCorrection()
        #expect(correction.flush().isEmpty)
        #expect(correction.status == ClockDriftCorrection.Status(clockDriftPpm: nil, applied: 0, remaining: nil))
    }
}
