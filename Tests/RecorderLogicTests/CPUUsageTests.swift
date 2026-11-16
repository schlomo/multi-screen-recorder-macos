import Testing
@testable import RecorderLogic

@Suite struct CPUUsageTests {
    @Test func eachSampleIsThePercentOfOneCoreAndTheAverageAndPeakFollow() {
        var usage = CPUUsage()
        usage.sample(cpuSeconds: 10, at: 100)
        #expect(usage.currentPercent == nil)
        #expect(usage.manifestEntry == nil)
        usage.sample(cpuSeconds: 10.25, at: 101)
        #expect(usage.currentPercent == 25)
        usage.sample(cpuSeconds: 11.75, at: 102)
        #expect(usage.currentPercent == 150)
        #expect(usage.text == "CPU 150 %")
        usage.sample(cpuSeconds: 11.85, at: 103)
        #expect(usage.peakPercent == 150)
        #expect(usage.manifestEntry == RecordingManifest.CPU(averagePercent: 61.7, peakPercent: 150))
    }
}
