import Foundation
import Testing
@testable import RecorderLogic

@Suite struct ClockDriftResamplerTests {
    private let sampleRate = 48_000.0

    private func sine(frequency: Double, amplitude: Double = 0.5, count: Int) -> [Float] {
        (0..<count).map { Float(amplitude * sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
    }

    /// Everything through one resampler at `rate`, in chunks of `chunk` samples.
    private func resample(_ channels: [[Float]], rate: Double, chunk: Int = 512) -> [[Float]] {
        var resampler = ClockDriftResampler(channelCount: channels.count)
        var output = Array(repeating: [Float](), count: channels.count)
        var start = 0
        let count = channels[0].count
        while start < count {
            let end = min(count, start + chunk)
            let part = resampler.process(channels.map { Array($0[start..<end]) }, rate: rate)
            for channel in output.indices { output[channel] += part[channel] }
            start = end
        }
        let tail = resampler.flush(rate: rate)
        for channel in output.indices { output[channel] += tail[channel] }
        return output
    }

    /// The least-squares fit of a sine of the angular frequency `omega` per
    /// sample to `samples`: its amplitude and the signal-to-noise ratio in dB.
    private func fit(_ samples: ArraySlice<Float>, omega: Double) -> (amplitude: Double, snr: Double) {
        // Normal equations for a·sin + b·cos + c.
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        var vector = [Double](repeating: 0, count: 3)
        for (index, sample) in zip(samples.indices, samples) {
            let basis = [sin(omega * Double(index)), cos(omega * Double(index)), 1]
            for row in 0..<3 {
                vector[row] += basis[row] * Double(sample)
                for column in 0..<3 { matrix[row][column] += basis[row] * basis[column] }
            }
        }
        let solution = solve(matrix, vector)
        var signal = 0.0
        var noise = 0.0
        for (index, sample) in zip(samples.indices, samples) {
            let fitted = solution[0] * sin(omega * Double(index)) + solution[1] * cos(omega * Double(index)) + solution[2]
            signal += fitted * fitted
            noise += (Double(sample) - fitted) * (Double(sample) - fitted)
        }
        return ((solution[0] * solution[0] + solution[1] * solution[1]).squareRoot(), 10 * log10(signal / noise))
    }

    private func solve(_ matrix: [[Double]], _ vector: [Double]) -> [Double] {
        var a = matrix
        var b = vector
        for pivot in 0..<3 {
            for row in (pivot + 1)..<3 {
                let factor = a[row][pivot] / a[pivot][pivot]
                for column in pivot..<3 { a[row][column] -= factor * a[pivot][column] }
                b[row] -= factor * b[pivot]
            }
        }
        var x = [Double](repeating: 0, count: 3)
        for row in stride(from: 2, through: 0, by: -1) {
            x[row] = (b[row] - ((row + 1)..<3).reduce(0) { $0 + a[row][$1] * x[$1] }) / a[row][row]
        }
        return x
    }

    @Test(arguments: [116e-6, -116e-6, 1000e-6])
    func aSineComesOutAtTheExpectedFrequencyAndClean(rate: Double) {
        let output = resample([sine(frequency: 1000, count: 24_000)], rate: rate)[0]
        let result = fit(output[100..<(output.count - 100)], omega: 2 * Double.pi * 1000 / sampleRate / (1 + rate))
        #expect(result.snr >= 90, "\(result.snr) dB")
        #expect(abs(result.amplitude - 0.5) < 0.001)
    }

    @Test func eighteenKilohertzKeepsItsAmplitude() {
        let rate = 116e-6
        let output = resample([sine(frequency: 18_000, count: 24_000)], rate: rate)[0]
        let result = fit(output[100..<(output.count - 100)], omega: 2 * Double.pi * 18_000 / sampleRate / (1 + rate))
        #expect(abs(20 * log10(result.amplitude / 0.5)) < 0.1, "\(result.amplitude)")
        #expect(result.snr >= 60, "\(result.snr) dB")
    }

    @Test(arguments: [116e-6, -116e-6, 1000e-6, -1000e-6])
    func theOutputCountFollowsTheRate(rate: Double) {
        let count = 96_000
        let output = resample([[Float](repeating: 0.1, count: count)], rate: rate)[0]
        #expect(abs(Double(output.count) - Double(count) * (1 + rate)) <= 1, "\(output.count)")
    }

    @Test func theOutputIsTheSameWhateverTheInputIsCutInto() {
        let input = [sine(frequency: 997, count: 20_000)]
        let whole = resample(input, rate: 333e-6, chunk: 20_000)
        for chunk in [1, 7, 512, 4099] {
            #expect(resample(input, rate: 333e-6, chunk: chunk) == whole)
        }
    }

    @Test func twoChannelsGetTheSameTreatment() {
        let one = sine(frequency: 440, count: 10_000)
        let output = resample([one, one], rate: -250e-6)
        #expect(output[0] == output[1])
        #expect(output[0] == resample([one], rate: -250e-6)[0])
    }

    @Test func aRateChangeMidStreamLeavesNoClick() {
        let amplitude = 0.5
        let input = sine(frequency: 1000, amplitude: amplitude, count: 48_000)
        var resampler = ClockDriftResampler(channelCount: 1)
        var output: [Float] = []
        for (index, start) in stride(from: 0, to: input.count, by: 512).enumerated() {
            let rate = index % 20 < 10 ? 1000e-6 : -1000e-6
            output += resampler.process([Array(input[start..<min(input.count, start + 512)])], rate: rate)[0]
        }
        // The steepest step a 1 kHz sine of this amplitude takes from one sample to the next.
        let steepest = amplitude * 2 * sin(Double.pi * 1000 / sampleRate * 1.001)
        let steps = zip(output.dropFirst(100), output.dropFirst(101)).map { abs(Double($1 - $0)) }
        #expect(steps.max()! <= steepest * 1.001, "\(steps.max()!) against \(steepest)")
    }

    @Test func theAppliedCorrectionIsTheOutputAgainstTheInputPosition() {
        var resampler = ClockDriftResampler(channelCount: 1)
        #expect(resampler.applied == 0)
        _ = resampler.process([[Float](repeating: 0, count: 48_000)], rate: 1000e-6)
        _ = resampler.flush(rate: 1000e-6)
        #expect(abs(resampler.applied - 0.001) < 1.0 / sampleRate)
        #expect(resampler.inputCount == 48_000)
    }
}
