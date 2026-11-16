import Foundation
import Testing
@testable import RecorderLogic

@Suite struct ClockDriftCorrectionTests {
    private let sampleRate = 48_000.0

    /// Clicks of a device 500 ppm slow at known shared clock times, with
    /// jittered arrivals: each comes out at its time once the correction
    /// has caught up (it starts after 5 intervals and settles within 15 s).
    @Test func clicksComeOutAtTheirSharedClockTimes() throws {
        let device = SimulatedDevice.steady(ppm: -500)
        let seconds = 60.0
        let buffers = device.buffers(for: seconds)
        // A click at the shared clock time T is at the device's sample T · rate / (1 + 500 ppm).
        let clicks = stride(from: 0.75, to: seconds - 1, by: 1.0).map { $0 }
        var input = [Float](repeating: 0, count: buffers.count * device.bufferSamples)
        for click in clicks { input[Int((click * sampleRate / (1 + 500e-6)).rounded())] = 1 }

        var correction = ClockDriftCorrection()
        var corrected: [ClockDriftCorrection.CorrectedAudio] = []
        for buffer in buffers {
            let start = buffer.index * device.bufferSamples
            corrected += correction.correct([Array(input[start..<(start + device.bufferSamples)])], at: buffer.time, arrival: buffer.arrival).audio
        }
        corrected += correction.flush()

        // Each click is the loudest output sample within 50 ms of its time.
        var loudest = [(seconds: Double, sample: Float)](repeating: (0, 0), count: clicks.count)
        for audio in corrected {
            for (index, sample) in audio.channels[0].enumerated() {
                let at = Double(audio.time) / 1e9 + Double(index) / sampleRate
                let click = Int((at - clicks[0]).rounded())
                guard clicks.indices.contains(click), abs(at - clicks[click]) < 0.05, sample > loudest[click].sample else { continue }
                loudest[click] = (at, sample)
            }
        }
        for (click, found) in zip(clicks, loudest) {
            let bound = click < 15 ? 0.0035 : click < 40 ? 0.001 : 0.0005
            #expect(abs(found.seconds - click) < bound, "the click at \(click) s came at \(found.seconds) s")
        }
        let status = correction.status
        #expect(abs(try #require(status.clockDriftPpm) - -500) < 10, "\(status.clockDriftPpm ?? 0) ppm")
        #expect(abs(status.applied - 0.03) < 0.0005, "\(status.applied * 1000) ms")
        #expect(abs(try #require(status.remaining)) < 0.0005)
    }

    /// A gap at 65 s, the correction well above 1 ms by then: the segment
    /// after it starts at its own timestamp plus the correction applied,
    /// a jump of exactly the gap's length.
    @Test func aGapComesOutAsAJumpOfItsLengthWithNothingLostBefore() throws {
        let device = SimulatedDevice.steady(ppm: -500)
        let buffers = device.buffers(for: 70)
        let gapLength: Int64 = 100_000_000
        let gapAt = 65 * 48_000 / device.bufferSamples
        var correction = ClockDriftCorrection()
        var before: [ClockDriftCorrection.CorrectedAudio] = []
        var after: [ClockDriftCorrection.CorrectedAudio] = []
        var gaps: [ClockDriftCorrection.Gap] = []
        let samples = [Float](repeating: 0.25, count: device.bufferSamples)
        for buffer in buffers {
            let isAfter = buffer.index >= gapAt
            let time = buffer.time + (isAfter ? gapLength : 0)
            let (audio, gap) = correction.correct([samples], at: time, arrival: buffer.arrival + (isAfter ? gapLength : 0))
            gaps += gap.map { [$0] } ?? []
            if buffer.index == gapAt {
                // The tail of the segment before, then the first corrected audio after.
                before += audio.dropLast()
                after += audio.suffix(1)
                let appliedAtGap = try #require(before.last).applied
                #expect(appliedAtGap > 0.001)
                #expect(try #require(after.first).time == time + Int64((appliedAtGap * 1e9).rounded()))
            } else if isAfter {
                after += audio
            } else {
                before += audio
            }
        }
        let gap = try #require(gaps.first)
        #expect(gaps.count == 1)
        #expect(gap.length == gapLength)
        #expect(gap.applied == before.last?.applied)
        #expect(gap.latenessBefore > 0 && gap.latenessAfter > 0)
        let output = before.reduce(0) { $0 + $1.channels[0].count }
        let appliedAtGap = try #require(before.last).applied
        // Every sample before the gap came out: the input and the correction applied.
        let input = Double(gapAt * device.bufferSamples)
        #expect(abs(Double(output) - input - appliedAtGap * sampleRate) <= 1)
        let end = Double(try #require(before.first).time) + Double(output) / sampleRate * 1e9
        let jump = Double(try #require(after.first).time) - end
        #expect(abs(jump - Double(gapLength)) <= 1e9 / sampleRate, "\(jump) ns")
        // Within a segment the corrected audio follows by sample count.
        for (audio, next) in zip(before, before.dropFirst()) {
            #expect(abs(Double(next.time - audio.time) - Double(audio.channels[0].count) / sampleRate * 1e9) <= 1)
        }
    }

    @Test func aChannelCountChangeStartsANewSegment() {
        var correction = ClockDriftCorrection()
        let mono = [[Float](repeating: 0.25, count: 512)]
        let stereo = mono + mono
        var monoAudio = correction.correct(mono, at: 0, arrival: 20_000_000).audio
        monoAudio += correction.correct(mono, at: 10_666_666, arrival: 30_000_000).audio
        #expect(monoAudio.allSatisfy { $0.channels.count == 1 })
        let monoOut = monoAudio.reduce(0) { $0 + $1.channels[0].count }
        let (changed, gap) = correction.correct(stereo, at: 21_333_333, arrival: 40_000_000)
        #expect(gap == nil)
        #expect(changed.map(\.channels.count) == [1, 2])
        #expect(monoOut + changed[0].channels[0].count == 1024)
        // The new segment starts at its own timestamp, the correction applied so far added.
        #expect(changed[1].time == 21_333_333)
        #expect(changed[1].channels[0].count == 512 - RecorderValues.clockDriftResamplerTaps / 2)
    }

    @Test func noBufferNoCorrectedAudio() {
        var correction = ClockDriftCorrection()
        #expect(correction.flush().isEmpty)
        #expect(correction.status == ClockDriftCorrection.Status(clockDriftPpm: nil, applied: 0, remaining: nil))
    }
}
