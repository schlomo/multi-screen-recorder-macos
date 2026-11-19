import AVFoundation
import CoreAudio
import EndToEndLogic
import Foundation

/// Plays the test tone into the loopback device, never into the default
/// output, so it is not heard on the Mac's speakers.
final class TonePlayer {
    private let engine = AVAudioEngine()

    init(deviceUID: String) throws {
        guard let device = CoreAudioDevices.device(uid: deviceUID), let rate = CoreAudioDevices.sampleRate(device) else {
            throw DriverError("the loopback device \(deviceUID) is gone")
        }
        try engine.outputNode.auAudioUnit.setDeviceID(device)
        let tone = TestTone(sampleRate: rate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            throw DriverError("no stereo format at \(rate) Hz")
        }
        let counter = SampleCounter()
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let first = counter.advance(by: Int64(frameCount))
            for frame in 0..<Int(frameCount) {
                let sample = tone.sample(at: first + Int64(frame))
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
    }

    func start() throws {
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
    }
}

/// The tone's sample count, touched only by the render thread.
private final class SampleCounter: @unchecked Sendable {
    private var next: Int64 = 0

    func advance(by count: Int64) -> Int64 {
        defer { next += count }
        return next
    }
}
