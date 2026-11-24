import Dispatch
import RecorderLogic
import Synchronization

/// The guide tracks of a recording (D31, D49): audio captures hand their
/// buffers in, and every `guideTrackInterval` the mixes, `guideTrackDelay`
/// behind real time, each audio input placed by its audio delay (D80), go
/// to every screen file listening. Thread-safe.
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

    /// A screen file's ticker listens from now on, until it stops; the
    /// listener runs under the feed's lock, so it only queues the samples.
    func listen(_ listener: @escaping Listener) -> Int {
        state.withLock { state in
            state.nextListener += 1
            state.listeners[state.nextListener] = listener
            return state.nextListener
        }
    }

    /// The listener stops, in one step with a peek at every guide track's
    /// samples not mixed yet up to the sample position `end`: every
    /// hand-over before it reached the listener, so the peeks start where
    /// those ended. Without `end`, no peek.
    func stopListening(_ id: Int, peekingUpTo end: Int64?) -> [GuideTrack: GuideLastMix.Peek] {
        state.withLock { state in
            guard state.listeners.removeValue(forKey: id) != nil, let end else { return [:] }
            return state.mixes.mapValues { mix in
                let peek = mix.peek(upTo: end)
                return GuideLastMix.Peek(start: peek.start, channels: peek.channels)
            }
        }
    }

    /// Waits until every guide track's sources have delivered their
    /// samples up to the sample position `end`, for at most `bound`;
    /// whether they did.
    func waitUntilReceived(upTo end: Int64, bound: Duration) async -> Bool {
        let clock = SuspendingClock()
        let deadline = clock.now + bound
        while true {
            if state.withLock({ $0.mixes.values.allSatisfy { $0.hasReceived(upTo: end) } }) { return true }
            guard clock.now < deadline else { return false }
            try? await clock.sleep(for: .milliseconds(10))
        }
    }

    /// An audio source joins its guide track, if the recording has it, placed `earlierBy` samples earlier;
    /// nil: not mixed until it is placed (D80).
    func add(source name: String, channelCount: Int, earlierBy: Int64? = 0, to guide: GuideTrack) {
        state.withLock { state in
            guard state.mixes[guide] != nil, state.mixes[guide]?.contains(source: name) == false else { return }
            state.mixes[guide]?.add(source: name, channelCount: channelCount, earlierBy: earlierBy)
        }
    }

    /// A source's placement in its guide track changes (`GuideTrackMix.place`), if it is in it.
    func place(source name: String, earlierBy: Int64?, in guide: GuideTrack) {
        state.withLock { state in
            guard state.mixes[guide]?.contains(source: name) == true else { return }
            state.mixes[guide]?.place(source: name, earlierBy: earlierBy)
        }
    }

    /// Whether the source is mixed: in its guide track with a placement.
    func isMixed(source name: String, in guide: GuideTrack) -> Bool {
        state.withLock { $0.mixes[guide]?.isMixed(source: name) == true }
    }

    /// The sample position the guide track's next mix starts at, if the recording has it.
    func mixedUpTo(_ guide: GuideTrack) -> Int64? {
        state.withLock { $0.mixes[guide]?.mixedUpTo }
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

    /// Mixes and hands over under the lock, so a listener that stops
    /// listening has every hand-over before it; a listener only queues.
    private func handOver() {
        let now = now()
        state.withLock { state in
            for track in tracks {
                guard var mix = state.mixes[track] else { continue }
                let start = mix.mixedUpTo
                let channels = mix.mix(until: now)
                state.mixes[track] = mix
                guard channels.first?.isEmpty == false else { continue }
                for listener in state.listeners.values { listener(track, channels, start) }
            }
        }
    }
}
