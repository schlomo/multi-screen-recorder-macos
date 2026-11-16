import Dispatch
import RecorderLogic
import Synchronization

/// The guide tracks of a recording (D31, D49): audio captures hand their
/// buffers in, and every `guideTrackInterval` the mixes, `guideTrackDelay`
/// behind real time, go to every display file listening. Thread-safe.
public final class GuideTrackFeed: Sendable {
    public typealias Listener = @Sendable (_ guide: GuideTrack, _ channels: [[Float]], _ positionFromStart: Int64) -> Void

    private struct State {
        var mixes: [GuideTrack: GuideTrackMix]
        var listeners: [Int: Listener] = [:]
        var nextListener = 0
    }

    public let tracks: [GuideTrack]
    private let state: Mutex<State>
    private let now: @Sendable () -> Int64
    private let timer: DispatchSourceTimer

    /// `now` is the time on the shared clock.
    init(tracks: [GuideTrack], now: @escaping @Sendable () -> Int64) {
        self.tracks = tracks
        self.now = now
        let start = now() - RecorderValues.guideTrackDelay.nanoseconds
        state = Mutex(State(mixes: Dictionary(uniqueKeysWithValues: tracks.map { track in
            var mix = GuideTrackMix(track)
            mix = GuideTrackMix(track, startingAt: mix.position(of: start))
            return (track, mix)
        })))
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "msr.guide-tracks", qos: .userInitiated))
        // Activated now: a `DispatchSourceTimer` never activated traps when
        // released, as when a recording fails to start before `start`. It
        // fires only once `start` schedules it.
        timer.activate()
    }

    func start() {
        let interval = DispatchTimeInterval.nanoseconds(Int(RecorderValues.guideTrackInterval.nanoseconds))
        timer.setEventHandler { [weak self] in self?.handOver() }
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(5))
    }

    func stop() {
        timer.cancel()
    }

    /// A display file's ticker listens from now on, until it is removed.
    func listen(_ listener: @escaping Listener) -> Int {
        state.withLock { state in
            state.nextListener += 1
            state.listeners[state.nextListener] = listener
            return state.nextListener
        }
    }

    func stopListening(_ id: Int) {
        _ = state.withLock { $0.listeners.removeValue(forKey: id) }
    }

    /// An audio source joins its guide track, if the recording has it.
    func add(source name: String, channelCount: Int, to guide: GuideTrack) {
        state.withLock { state in
            guard state.mixes[guide] != nil, state.mixes[guide]?.contains(source: name) == false else { return }
            state.mixes[guide]?.add(source: name, channelCount: channelCount)
        }
    }

    func remove(source name: String, from guide: GuideTrack) {
        state.withLock { state in
            guard state.mixes[guide]?.contains(source: name) == true else { return }
            state.mixes[guide]?.remove(source: name)
        }
    }

    func receive(_ channels: [[Float]], from name: String, to guide: GuideTrack, at time: Int64) {
        state.withLock { state in
            guard state.mixes[guide]?.contains(source: name) == true else { return }
            state.mixes[guide]?.receive(channels, from: name, at: time)
        }
    }

    private func handOver() {
        let now = now()
        let (mixed, listeners) = state.withLock { state -> ([(GuideTrack, [[Float]], Int64)], [Listener]) in
            var mixed: [(GuideTrack, [[Float]], Int64)] = []
            for track in tracks {
                guard var mix = state.mixes[track] else { continue }
                let start = mix.mixedUpTo
                let channels = mix.mix(until: now)
                state.mixes[track] = mix
                if channels.first?.isEmpty == false { mixed.append((track, channels, start)) }
            }
            return (mixed, Array(state.listeners.values))
        }
        for (track, channels, start) in mixed {
            for listener in listeners { listener(track, channels, start) }
        }
    }
}
