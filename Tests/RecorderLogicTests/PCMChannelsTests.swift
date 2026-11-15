import Testing
@testable import RecorderLogic

@Suite struct PCMChannelsTests {
    @Test func interleavedPCMIsSplitFrameByFrame() throws {
        let samples: [Float] = [0.1, -0.1, 0.2, -0.2, 0.3, -0.3]
        let channels = try samples.withUnsafeBytes { bytes in
            try splitIntoChannels([bytes], layout: PCMLayout(channelCount: 2, isInterleaved: true, sampleFormat: .float32))
        }
        #expect(channels == [[0.1, 0.2, 0.3], [-0.1, -0.2, -0.3]])
    }

    @Test func nonInterleavedPCMKeepsOneBufferPerChannel() throws {
        let first: [Float] = [0.1, 0.2]
        let second: [Float] = [-0.5, -0.6]
        let third: [Float] = [1, -1]
        let channels = try first.withUnsafeBytes { a in
            try second.withUnsafeBytes { b in
                try third.withUnsafeBytes { c in
                    try splitIntoChannels([a, b, c], layout: PCMLayout(channelCount: 3, isInterleaved: false, sampleFormat: .float32))
                }
            }
        }
        #expect(channels == [[0.1, 0.2], [-0.5, -0.6], [1, -1]])
    }

    @Test func integerPCMBecomesFloatsFromMinusOneToOne() throws {
        let samples: [Int16] = [16384, -32768, 0, 32767]
        let channels = try samples.withUnsafeBytes { bytes in
            try splitIntoChannels([bytes], layout: PCMLayout(channelCount: 2, isInterleaved: true, sampleFormat: .int16))
        }
        #expect(channels[0] == [0.5, 0])
        #expect(channels[1][0] == -1)
        #expect(abs(channels[1][1] - 1) < 0.0001)
        let wide: [Int32] = [Int32.min, 1 << 30]
        let mono = try wide.withUnsafeBytes { bytes in
            try splitIntoChannels([bytes], layout: PCMLayout(channelCount: 1, isInterleaved: true, sampleFormat: .int32))
        }
        #expect(mono == [[-1, 0.5]])
    }

    @Test func aBufferThatDoesNotMatchItsLayoutIsAnError() {
        let samples: [Float] = [0.1, 0.2, 0.3]
        #expect(throws: PCMLayoutError.self) {
            try samples.withUnsafeBytes { bytes in
                try splitIntoChannels([bytes], layout: PCMLayout(channelCount: 2, isInterleaved: true, sampleFormat: .float32))
            }
        }
        #expect(throws: PCMLayoutError.self) {
            try samples.withUnsafeBytes { bytes in
                try splitIntoChannels([bytes], layout: PCMLayout(channelCount: 2, isInterleaved: false, sampleFormat: .float32))
            }
        }
    }
}
