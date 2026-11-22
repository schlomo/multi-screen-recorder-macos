import Foundation
import Testing
@testable import RecorderLogic

@Suite struct AudioLevelMeterTests {
    private let millisecond: Int64 = 1_000_000

    @Test func theLevelIsTheHighestSamplePeakOfAnyChannelSinceTheLastReading() {
        var meter = AudioLevelMeter()
        meter.measure([[0.1, -0.3], [0.2, 0.05]], at: 0)
        meter.measure([[0.25, 0], [-0.1, 0]], at: 10 * millisecond)
        #expect(meter.read(at: 20 * millisecond).peak == 0.3)
        meter.measure([[0.05]], at: 120 * millisecond)
        #expect(meter.read(at: 120 * millisecond).peak == 0.05)
    }

    @Test func withoutABufferSinceTheLastReadingTheLevelIsSilent() {
        var meter = AudioLevelMeter()
        meter.measure([[0.5]], at: 0)
        _ = meter.read(at: 0)
        let level = meter.read(at: 100 * millisecond)
        #expect(level.peak == 0)
        #expect(level.peakDBFS == nil)
        #expect(level.peakFraction == 0)
    }

    /// The window may open long after a loud buffer: its first reading
    /// shows no older peak than the peak hold.
    @Test func whileNobodyReadsAPeakOlderThanThePeakHoldIsForgotten() {
        var meter = AudioLevelMeter()
        meter.measure([[0.9]], at: 0)
        meter.measure([[0.1]], at: 60_000 * millisecond)
        let level = meter.read(at: 60_050 * millisecond)
        #expect(level.peak == 0.1)
        #expect(level.hold == 0.1)
    }

    @Test func thePeakHoldKeepsTheHighestPeakFor1Point5Seconds() {
        var meter = AudioLevelMeter()
        meter.measure([[0.8]], at: 0)
        _ = meter.read(at: 0)
        meter.measure([[0.1]], at: 1000 * millisecond)
        #expect(meter.read(at: 1000 * millisecond).hold == 0.8)
        meter.measure([[0.1]], at: 1499 * millisecond)
        #expect(meter.read(at: 1499 * millisecond).hold == 0.8)
        meter.measure([[0.1]], at: 1500 * millisecond)
        #expect(meter.read(at: 1500 * millisecond).hold == 0.1)
    }

    @Test func aHigherPeakTakesTheHoldAtOnceAndStartsItsTimeOver() {
        var meter = AudioLevelMeter()
        meter.measure([[0.4]], at: 0)
        meter.measure([[0.6]], at: 1000 * millisecond)
        #expect(meter.read(at: 1000 * millisecond).hold == 0.6)
        #expect(meter.read(at: 2400 * millisecond).hold == 0.6)
        #expect(meter.read(at: 2500 * millisecond).hold == 0)
    }

    @Test func decibelsFullScaleOnTheScaleFromMinus60To0() {
        #expect(AudioLevel.decibels(1) == 0)
        #expect(abs(AudioLevel.decibels(0.5)! - -6.0206) < 0.001)
        #expect(AudioLevel.decibels(0) == nil)
        #expect(AudioLevel.fraction(ofDBFS: 0) == 1)
        #expect(AudioLevel.fraction(ofDBFS: -30) == 0.5)
        #expect(AudioLevel.fraction(ofDBFS: -60) == 0)
        #expect(AudioLevel.fraction(ofDBFS: -90) == 0)
        #expect(AudioLevel.fraction(ofDBFS: nil) == 0)
        // A float sample may exceed full scale; the bar ends at 0 dBFS.
        #expect(AudioLevel.fraction(ofDBFS: 3) == 1)
    }

    @Test func aLevelIsRedFromMinus1DecibelFullScale() {
        let red = Float(pow(10, -0.99 / 20))
        let notRed = Float(pow(10, -1.01 / 20))
        #expect(AudioLevel(peak: red, hold: red).peakIsRed)
        #expect(AudioLevel(peak: red, hold: red).holdIsRed)
        #expect(!AudioLevel(peak: notRed, hold: 1).peakIsRed)
        #expect(AudioLevel(peak: notRed, hold: 1).holdIsRed)
        #expect(!AudioLevel.silent.peakIsRed)
    }
}
