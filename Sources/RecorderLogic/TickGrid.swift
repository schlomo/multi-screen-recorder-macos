/// The ticks of a recording: tick k is at t0 + k / framesPerSecond seconds,
/// computed, never accumulated (D11, D21).
public struct TickGrid: Equatable, Sendable {
    public let framesPerSecond: Int

    public init(framesPerSecond: Int) {
        precondition(framesPerSecond > 0, "a tick grid needs a positive frame rate")
        self.framesPerSecond = framesPerSecond
    }

    /// The recording's grid.
    public static let recording = TickGrid(framesPerSecond: RecorderValues.framesPerSecond)

    private static let nanosecondsPerSecond: Int64 = 1_000_000_000

    /// The time of tick k in nanoseconds from t0, rounded down.
    public func time(ofTick tick: Int64) -> Int64 {
        tick * Self.nanosecondsPerSecond / Int64(framesPerSecond)
    }

    /// The first tick at or after a time: where a frame captured then first appears.
    public func firstTick(atOrAfter time: Int64) -> Int64 {
        guard time > 0 else { return 0 }
        let rate = Int64(framesPerSecond)
        return (time * rate + Self.nanosecondsPerSecond - 1) / Self.nanosecondsPerSecond
    }

    /// The last tick at or before a time, or nil before t0.
    public func lastTick(atOrBefore time: Int64) -> Int64? {
        guard time >= 0 else { return nil }
        let tick = time * Int64(framesPerSecond) / Self.nanosecondsPerSecond
        // Rounding down in `time(ofTick:)` can put the next tick at `time` itself.
        return self.time(ofTick: tick + 1) <= time ? tick + 1 : tick
    }

    /// Seconds from t0 of tick k, as the recording manifest gives them.
    public func seconds(ofTick tick: Int64) -> Double {
        Double(tick) / Double(framesPerSecond)
    }
}

/// One video file's ticks: every tick writes the newest frame captured at
/// or before it, with exactly the tick's time. A tick is decided at its
/// time, or with a decision delay once a frame captured after it has
/// arrived or the delay has passed, whichever is first; a frame arriving
/// after its tick was decided goes to the next tick decided and is counted.
/// No tick is dropped: a tick the writer cannot take waits, carrying the
/// frame chosen at its own time, and is written late and counted. More
/// than `lateTickBound` ticks waiting means the writer fell behind.
public struct TickLoop<Frame> {
    public enum Outcome: Equatable, Sendable {
        case running
        case writerFellBehind
    }

    public let grid: TickGrid
    public let lateTickBound: Int
    /// The file's first tick: the first after the first frame that passed the screen check.
    public private(set) var firstTick: Int64?
    /// The next tick to choose a frame for.
    public private(set) var nextTick: Int64 = 0
    /// The last tick written, nil before the first.
    public private(set) var lastWrittenTick: Int64?
    /// Ticks written late because the writer was not ready.
    public private(set) var framesRepeatedForLateness = 0
    /// Frames that arrived after their tick was decided and were written on a
    /// later one; a late frame superseded before any tick shows it is not counted.
    public private(set) var framesPlacedLate = 0
    /// The longest a frame placed late took from its capture to its arrival, in nanoseconds.
    public private(set) var largestLateArrival: Int64 = 0

    /// Frames in order of capture: the newest at or before the last chosen
    /// tick, and any captured after it; a late one with how late it arrived, until a tick shows it.
    private var frames: [(time: Int64, frame: Frame, lateArrival: Int64?)] = []
    private var waiting: [(tick: Int64, frame: Frame, isLate: Bool)] = []

    /// The capture's start: the file's first tick is never before it.
    public let notBefore: Int64
    /// How long after its time a tick waits for a frame captured after it, in nanoseconds.
    public let decisionDelay: Int64

    public init(
        grid: TickGrid = .recording, lateTickBound: Int = RecorderValues.lateTickBound, notBefore: Int64 = 0,
        decisionDelay: Int64 = 0
    ) {
        self.grid = grid
        self.lateTickBound = lateTickBound
        self.notBefore = notBefore
        self.decisionDelay = decisionDelay
    }

    public var waitingTicks: Int { waiting.count }

    /// A frame that passed the screen check, captured at `time` and arrived
    /// at `arrival` (nanoseconds from t0; nil: at its capture). The first
    /// one decides the file's first tick. A frame older than the newest one
    /// kept is ignored: frames arrive in capture order.
    public mutating func receive(_ frame: Frame, capturedAt time: Int64, arrivedAt arrival: Int64? = nil) {
        if let newest = frames.last, time < newest.time { return }
        var lateArrival: Int64?
        if let firstTick {
            if nextTick > firstTick, time <= grid.time(ofTick: nextTick - 1) { lateArrival = (arrival ?? time) - time }
        } else {
            let tick = grid.firstTick(atOrAfter: max(time, notBefore))
            firstTick = tick
            nextTick = tick
        }
        frames.append((time, frame, lateArrival))
    }

    /// Chooses a frame for every tick decided by `now` and hands the
    /// waiting ticks, oldest first, to `write`, which returns false when the
    /// writer is not ready; the rest wait for the next call. At the file's
    /// end, `waitingForLateFrames` false decides every tick due by `now`.
    public mutating func advance(
        to now: Int64, waitingForLateFrames: Bool = true, write: (Int64, Frame) throws -> Bool
    ) rethrows -> Outcome {
        guard firstTick != nil, let lastDue = grid.lastTick(atOrBefore: now) else { return .running }
        while nextTick <= lastDue {
            let tickTime = grid.time(ofTick: nextTick)
            if waitingForLateFrames, now - tickTime < decisionDelay, let newest = frames.last, newest.time <= tickTime { break }
            guard let chosen = frames.lastIndex(where: { $0.time <= tickTime }) else { break }
            waiting.append((nextTick, frames[chosen].frame, false))
            if let lateArrival = frames[chosen].lateArrival {
                framesPlacedLate += 1
                largestLateArrival = max(largestLateArrival, lateArrival)
                frames[chosen].lateArrival = nil
            }
            frames.removeFirst(chosen)
            nextTick += 1
        }
        while let first = waiting.first {
            guard try write(first.tick, first.frame) else { break }
            if first.isLate { framesRepeatedForLateness += 1 }
            lastWrittenTick = first.tick
            waiting.removeFirst()
        }
        for index in waiting.indices { waiting[index].isLate = true }
        return waiting.count > lateTickBound ? .writerFellBehind : .running
    }

    /// At the end of the file: hands the waiting ticks to `write` until it
    /// takes none; returns how many are left unwritten.
    public mutating func drain(write: (Int64, Frame) throws -> Bool) rethrows -> Int {
        while let first = waiting.first {
            guard try write(first.tick, first.frame) else { break }
            if first.isLate { framesRepeatedForLateness += 1 }
            lastWrittenTick = first.tick
            waiting.removeFirst()
        }
        for index in waiting.indices { waiting[index].isLate = true }
        return waiting.count
    }
}
