import AVFoundation
import CoreMedia
import Foundation
import RecorderLogic
@preconcurrency import ScreenCaptureKit

/// An audio input's buffers: one `AVCaptureSession` per recorded audio input
/// (D49), PCM as the device delivers it at the audio sample rate. An unplug
/// stops the session with `AVCaptureSession.runtimeErrorNotification`
/// (-11808) and `AVCaptureDevice.wasDisconnectedNotification`, both seen at
/// once on the owner's Mac (2026-11-15); the session does not resume by
/// itself, so the capture ends and a replug starts a new one.
final class MicrophoneSource: NSObject, AudioBufferSource, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let uid: String
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var state = State()

    private struct State {
        var session: AVCaptureSession?
        var deliver: (@Sendable (CMSampleBuffer) -> Void)?
        var ended: (@Sendable (AudioTracker.CaptureEnd) -> Void)?
        var observers: [any NSObjectProtocol] = []
        var isStopped = false
    }

    init(uid: String) {
        self.uid = uid
    }

    private func withState<Result>(_ body: (inout State) -> Result) -> Result {
        lock.withLock { body(&state) }
    }

    func start(
        queue: DispatchQueue, deliver: @escaping @Sendable (CMSampleBuffer) -> Void,
        ended: @escaping @Sendable (AudioTracker.CaptureEnd) -> Void
    ) {
        withState {
            $0.deliver = deliver
            $0.ended = ended
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                try open(queue: queue)
            } catch {
                endOnce(.captureFailed(error.localizedDescription))
            }
        }
    }

    private struct SourceError: LocalizedError {
        let errorDescription: String?
    }

    private func open(queue: DispatchQueue) throws {
        guard let device = AVCaptureDevice(uniqueID: uid) else {
            throw SourceError(errorDescription: "the audio input is not available to AVFoundation")
        }
        let input = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: RecorderValues.audioSampleRate,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw SourceError(errorDescription: "the capture session does not take the audio input")
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        let center = NotificationCenter.default
        let observers = [
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
                let disconnected = error?.domain == AVFoundationErrorDomain && error?.code == AVError.Code.deviceWasDisconnected.rawValue
                self?.endOnce(disconnected ? .disconnected : .captureFailed(
                    error.map { "\($0.localizedDescription) (\($0.domain) \($0.code))" } ?? "the capture session stopped"))
            },
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) { [weak self] _ in
                self?.endOnce(.disconnected)
            },
        ]
        let proceed = withState { state -> Bool in
            state.observers = observers
            guard !state.isStopped else { return false }
            state.session = session
            return true
        }
        guard proceed else {
            observers.forEach(center.removeObserver)
            return
        }
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        withState { $0.deliver }?(sampleBuffer)
    }

    private func endOnce(_ end: AudioTracker.CaptureEnd) {
        let ended = withState { state -> (@Sendable (AudioTracker.CaptureEnd) -> Void)? in
            defer { state.ended = nil }
            return state.isStopped ? nil : state.ended
        }
        ended?(end)
    }

    func stop() async {
        let (session, observers) = withState { state in
            state.isStopped = true
            state.deliver = nil
            state.ended = nil
            defer {
                state.session = nil
                state.observers = []
            }
            return (state.session, state.observers)
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        session?.stopRunning()
    }
}

/// The system audio's buffers: a ScreenCaptureKit stream with
/// `capturesAudio` and our own process's audio excluded, on the main display
/// as read when it starts, which `capturing` is told; its video at the
/// smallest size and rate and dropped (D49).
final class SystemAudioSource: NSObject, AudioBufferSource, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let capturing: @Sendable (CGDirectDisplayID) -> Void
    private let lifecycle = StreamLifecycle()
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var state = State()

    private struct State {
        var stream: SCStream?
        var deliver: (@Sendable (CMSampleBuffer) -> Void)?
        var ended: (@Sendable (AudioTracker.CaptureEnd) -> Void)?
        var isStopped = false
    }

    init(capturing: @escaping @Sendable (CGDirectDisplayID) -> Void) {
        self.capturing = capturing
    }

    private func withState<Result>(_ body: (inout State) -> Result) -> Result {
        lock.withLock { body(&state) }
    }

    func start(
        queue: DispatchQueue, deliver: @escaping @Sendable (CMSampleBuffer) -> Void,
        ended: @escaping @Sendable (AudioTracker.CaptureEnd) -> Void
    ) {
        withState {
            $0.deliver = deliver
            $0.ended = ended
        }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let mainDisplayID = CGMainDisplayID()
                guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) else {
                    endOnce(.disconnected)
                    return
                }
                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = true
                configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = RecorderValues.audioSampleRate
                configuration.channelCount = GuideTrack.systemAudio.channelCount
                // The video is not recorded: the smallest size and rate.
                configuration.width = 2
                configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                configuration.queueDepth = 3
                configuration.showsCursor = false
                let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                                      configuration: configuration, delegate: self)
                let proceed = withState { state -> Bool in
                    guard !state.isStopped else { return false }
                    state.stream = stream
                    return true
                }
                guard proceed else { return }
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                capturing(mainDisplayID)
                try await lifecycle.start(stream)
            } catch {
                endOnce(Self.captureEnd(for: error))
            }
        }
    }

    /// The display gone (`noCaptureSource`) is no failure.
    static func captureEnd(for error: any Error) -> AudioTracker.CaptureEnd {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.noCaptureSource.rawValue {
            return .disconnected
        }
        return .captureFailed("\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        withState { $0.deliver }?(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        endOnce(Self.captureEnd(for: error))
    }

    private func endOnce(_ end: AudioTracker.CaptureEnd) {
        let ended = withState { state -> (@Sendable (AudioTracker.CaptureEnd) -> Void)? in
            defer { state.ended = nil }
            return state.isStopped ? nil : state.ended
        }
        ended?(end)
    }

    func stop() async {
        let stream = withState { state in
            state.isStopped = true
            state.deliver = nil
            state.ended = nil
            defer { state.stream = nil }
            return state.stream
        }
        await lifecycle.stop()
        if let stream {
            try? stream.removeStreamOutput(self, type: .audio)
            try? stream.removeStreamOutput(self, type: .screen)
        }
    }
}
