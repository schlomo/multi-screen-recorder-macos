/// How a buffer of linear PCM lays out its samples, as Core Audio describes
/// it: interleaved, one buffer holding every channel frame by frame, or
/// non-interleaved, one buffer per channel.
public struct PCMLayout: Equatable, Sendable {
    public enum SampleFormat: Equatable, Sendable {
        case float32
        case int16
        case int32
    }

    public let channelCount: Int
    public let isInterleaved: Bool
    public let sampleFormat: SampleFormat

    public init(channelCount: Int, isInterleaved: Bool, sampleFormat: SampleFormat) {
        self.channelCount = channelCount
        self.isInterleaved = isInterleaved
        self.sampleFormat = sampleFormat
    }

    var bytesPerSample: Int {
        switch sampleFormat {
        case .float32, .int32: 4
        case .int16: 2
        }
    }
}

public struct PCMLayoutError: Error, Equatable, CustomStringConvertible {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

/// Splits a buffer of PCM into one array of samples per channel, as
/// floats from -1 to 1: an audio input's channels each become a mono
/// audio track.
public func splitIntoChannels(_ buffers: [UnsafeRawBufferPointer], layout: PCMLayout) throws(PCMLayoutError) -> [[Float]] {
    let channelsPerBuffer = layout.isInterleaved ? layout.channelCount : 1
    let expectedBuffers = layout.isInterleaved ? 1 : layout.channelCount
    guard layout.channelCount > 0, buffers.count == expectedBuffers else {
        throw PCMLayoutError(description: "\(buffers.count) PCM buffers for \(layout.channelCount) channels, "
            + (layout.isInterleaved ? "interleaved" : "non-interleaved"))
    }
    let bytesPerFrame = layout.bytesPerSample * channelsPerBuffer
    let frameCount = buffers[0].count / bytesPerFrame
    for buffer in buffers where buffer.count != frameCount * bytesPerFrame {
        throw PCMLayoutError(description: "a PCM buffer of \(buffer.count) bytes does not hold whole frames of \(frameCount)")
    }
    var channels: [[Float]] = []
    for buffer in buffers {
        for channel in 0..<channelsPerBuffer {
            channels.append((0..<frameCount).map { frame in
                sample(in: buffer, at: frame * channelsPerBuffer + channel, format: layout.sampleFormat)
            })
        }
    }
    return channels
}

private func sample(in buffer: UnsafeRawBufferPointer, at index: Int, format: PCMLayout.SampleFormat) -> Float {
    switch format {
    case .float32:
        buffer.loadUnaligned(fromByteOffset: index * 4, as: Float.self)
    case .int16:
        Float(buffer.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)) / 32768
    case .int32:
        Float(Double(buffer.loadUnaligned(fromByteOffset: index * 4, as: Int32.self)) / 2_147_483_648)
    }
}
