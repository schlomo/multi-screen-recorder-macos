import AVFoundation
import CoreAudio
import EndToEndLogic
import Foundation
import Synchronization

/// Plays the test tone into the loopback device, never into the default
/// output, so it is not heard on the Mac's speakers. The tone follows each
/// render cycle's sample time, so a cycle the output skips does not shift
/// it; every skip and every overload the device tells of is kept as a
/// playback break.
final class TonePlayer {
    private let engine = AVAudioEngine()
    private let device: AudioObjectID
    private let seen = BreakLog()
    private let listenerQueue = DispatchQueue(label: "overloads")
    private var overloadListener: AudioObjectPropertyListenerBlock?
    private var overloadAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDeviceProcessorOverload, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    init(deviceUID: String) throws {
        guard let device = CoreAudioDevices.device(uid: deviceUID), let rate = CoreAudioDevices.sampleRate(device) else {
            throw DriverError("the loopback device \(deviceUID) is gone")
        }
        self.device = device
        try engine.outputNode.auAudioUnit.setDeviceID(device)
        let tone = TestTone(sampleRate: rate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            throw DriverError("no stereo format at \(rate) Hz")
        }
        let clock = RenderClock()
        let seen = self.seen
        let source = AVAudioSourceNode(format: format) { _, timestamp, frameCount, bufferList in
            let cycle = clock.render(sampleTime: timestamp.pointee.mSampleTime, frames: Int(frameCount))
            if let skipped = cycle.skipped { seen.add(skipped) }
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let sample = tone.sample(at: cycle.firstIndex + Int64(frame))
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
        let seen = self.seen
        let listener: AudioObjectPropertyListenerBlock = { _, _ in seen.add(nil) }
        let status = AudioObjectAddPropertyListenerBlock(device, &overloadAddress, listenerQueue, listener)
        guard status == noErr else { throw DriverError("cannot listen for the loopback device's overloads (status \(status))") }
        overloadListener = listener
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
        if let overloadListener {
            AudioObjectRemovePropertyListenerBlock(device, &overloadAddress, listenerQueue, overloadListener)
            self.overloadListener = nil
        }
    }

    /// The breaks so far, each at its time of the local day.
    func breaks() -> [PlaybackBreak] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return seen.all().map { seen in
            let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond],
                                                from: Date(timeIntervalSinceReferenceDate: seen.at))
            let seconds = Double((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0))
                + Double(parts.nanosecond ?? 0) / 1_000_000_000
            return PlaybackBreak(timeOfDay: seconds, samples: seen.samples)
        }
    }

    /// How many breaks there were, those beyond what the log holds included.
    var breakCount: Int { seen.count }
}

/// The breaks as the player sees them, from the render thread and the
/// overload listener: slots allocated up front and taken by an atomic
/// index, so adding one never locks or allocates; those beyond the
/// capacity are only counted. Read once playback has stopped.
private final class BreakLog: @unchecked Sendable {
    static let capacity = 1024
    private let times = UnsafeMutablePointer<Double>.allocate(capacity: capacity)
    private let samples = UnsafeMutablePointer<Int64>.allocate(capacity: capacity)
    private let next = Atomic<Int>(0)
    /// `samples` of an overload, which has no sample count.
    private static let overload = Int64.min

    deinit {
        times.deallocate()
        samples.deallocate()
    }

    func add(_ skipped: Int64?) {
        let slot = next.wrappingAdd(1, ordering: .sequentiallyConsistent).oldValue
        guard slot < Self.capacity else { return }
        times[slot] = Date.timeIntervalSinceReferenceDate
        samples[slot] = skipped ?? Self.overload
    }

    var count: Int { next.load(ordering: .sequentiallyConsistent) }

    func all() -> [(at: TimeInterval, samples: Int64?)] {
        (0..<min(count, Self.capacity)).map { slot in
            (times[slot], samples[slot] == Self.overload ? nil : samples[slot])
        }
    }
}

/// The playback clock, touched only by the render thread.
private final class RenderClock: @unchecked Sendable {
    private var clock = PlaybackClock()

    func render(sampleTime: Double, frames: Int) -> PlaybackClock.Cycle {
        clock.render(sampleTime: sampleTime, frames: frames)
    }
}
