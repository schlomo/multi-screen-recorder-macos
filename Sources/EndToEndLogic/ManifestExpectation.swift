import Foundation

/// A change the driver made during a recording: when it asked for it and
/// when it saw it done, in seconds after the recording's start.
public struct ChangeTimes: Sendable, Equatable {
    public var asked: Double
    public var done: Double
    /// When all screens had been unchanged for the settle time after it, as
    /// the driver watched them (`ScreenSettling`); nil when not watched.
    public var screensSettled: Double?

    public init(asked: Double, done: Double, screensSettled: Double? = nil) {
        self.asked = asked
        self.done = done
        self.screensSettled = screensSettled
    }

    /// Where a time the recorder writes for the change may lie, by its kind,
    /// widened by the tolerance: an immediate one from the ask to the done;
    /// a settled one from the ask plus the settle time to the moment the
    /// screens settled (the done plus the settle time when not watched).
    public func window(_ kind: TimingKind, settleTime: Double, tolerance: Double) -> ClosedRange<Double> {
        switch kind {
        case .immediate: (asked - tolerance)...(done + tolerance)
        case .settled: (asked + settleTime - tolerance)...((screensSettled ?? done + settleTime) + tolerance)
        }
    }

    public func windowWidth(_ kind: TimingKind, settleTime: Double, tolerance: Double) -> Double {
        let window = window(kind, settleTime: settleTime, tolerance: tolerance)
        return window.upperBound - window.lowerBound
    }
}

/// How a time the recorder writes follows the change it tells of.
public enum TimingKind: Sendable, Equatable {
    /// After the settle time: a screen file's start, `screen frame size
    /// changed`, a file's end at a mode switch.
    case settled
    /// With the change: `screen connected`, `screen disconnected`, a file's
    /// end at a disconnect.
    case immediate

    var description: String { self == .settled ? "the settle time after the change" : "with the change" }
}

/// A time the recorder writes: the change it follows, and how.
public struct ExpectedTime: Sendable, Equatable {
    public var change: ChangeTimes
    public var kind: TimingKind

    public init(change: ChangeTimes, kind: TimingKind) {
        self.change = change
        self.kind = kind
    }
}

/// What a scenario's recording manifest must say, built by the driver from
/// what it did: exact where the recording is deterministic (the settings,
/// the virtual screens and the audio inputs the driver plays into, how the
/// recording ended), and only well-formed and listed for the Mac's own
/// screens and audio inputs (docs/design/end-to-end-tests.md).
public struct ManifestExpectation: Sendable {
    public enum Ending: Sendable, Equatable {
        /// Stopped by Ctrl-C, SIGTERM or the duration: finalized, result ok.
        case finalized
        /// Killed (`kill -9`) at this many seconds after the start: never
        /// finalized, every file still `recording`.
        case killed(at: Double)
    }

    /// The settings as the manifest writes them.
    public struct Settings: Sendable, Equatable {
        public var resolution: String
        public var audioMode: String
        public var systemAudio: Bool

        public init(resolution: String, audioMode: String, systemAudio: Bool) {
            self.resolution = resolution
            self.audioMode = audioMode
            self.systemAudio = systemAudio
        }

        var json: JSONValue {
            .object(["resolution": .string(resolution), "audioMode": .string(audioMode), "systemAudio": .bool(systemAudio)])
        }

        /// The guide tracks of every screen file (recorder.md, "Guide tracks").
        var guideTracks: [String] {
            (audioMode == "none" ? [] : ["Audio inputs"]) + (systemAudio ? ["System audio"] : [])
        }
    }

    /// One screen file of a virtual screen, in the order they start.
    public struct VirtualScreenFile: Sendable, Equatable {
        public var screenUUID: String
        public var frameSize: [Int]
        /// The connect or mode switch its file starts after, the settle time later.
        public var startedBy: ChangeTimes
        /// The mode switch (settled) or disconnect (immediate) that ends it;
        /// nil when the recording ended first.
        public var endedBy: ExpectedTime?

        public init(screenUUID: String, frameSize: [Int], startedBy: ChangeTimes, endedBy: ExpectedTime?) {
            self.screenUUID = screenUUID
            self.frameSize = frameSize
            self.startedBy = startedBy
            self.endedBy = endedBy
        }
    }

    /// One event about a virtual screen, in order.
    public struct VirtualScreenEvent: Sendable, Equatable {
        public var event: String
        /// The change the event tells of, and how it follows it.
        public var expected: ExpectedTime

        public init(event: String, expected: ExpectedTime) {
            self.event = event
            self.expected = expected
        }
    }

    /// An audio input the driver plays into: recorded from the start, in
    /// one audio file, without any event.
    public struct PlayedAudioInput: Sendable, Equatable {
        public var name: String
        public var uid: String
        public var channels: Int

        public init(name: String, uid: String, channels: Int) {
            self.name = name
            self.uid = uid
            self.channels = channels
        }
    }

    public var app: String
    public var settings: Settings
    public var ending: Ending
    /// When the recording stopped, in seconds after its start: the
    /// duration, or when the driver sent the signal; for a kill, the kill.
    public var stoppedAt: Double

    /// Whether a time at which the recording or a file ended is not before
    /// the stop and within the finalize allowance after it.
    func endsAtTheStop(_ seconds: Double) -> Bool {
        seconds >= stoppedAt - timeTolerance && seconds <= stoppedAt + finalizeAllowance
    }

    /// The bounds of `endsAtTheStop`, for failure lines.
    var stopBounds: String {
        "\(ManifestCheck.seconds(stoppedAt - timeTolerance)) s to \(ManifestCheck.seconds(stoppedAt + finalizeAllowance)) s"
    }
    /// The Mac's own screens when the run started: they take the first numbers.
    public var ownScreenCount: Int
    /// The name every virtual screen's name starts with.
    public var virtualScreenNamePrefix: String
    public var virtualScreenFiles: [VirtualScreenFile]
    public var virtualScreenEvents: [VirtualScreenEvent]
    public var playedAudioInputs: [PlayedAudioInput]
    /// How far a time the recorder writes may be from the time the driver
    /// saw the change, in seconds, beyond the settle time.
    public var timeTolerance: Double
    /// How long after the stop the recording may end, in seconds: `ended`
    /// is written once every file is finalized, and the audio stops after
    /// the screens (D51).
    public var finalizeAllowance: Double
    /// How long a screen waits unchanged before its file starts.
    public var settleTime: Double

    public init(
        app: String, settings: Settings, ending: Ending, stoppedAt: Double, ownScreenCount: Int,
        virtualScreenNamePrefix: String, virtualScreenFiles: [VirtualScreenFile] = [],
        virtualScreenEvents: [VirtualScreenEvent] = [], playedAudioInputs: [PlayedAudioInput] = [],
        timeTolerance: Double, finalizeAllowance: Double, settleTime: Double
    ) {
        self.app = app
        self.settings = settings
        self.ending = ending
        self.stoppedAt = stoppedAt
        self.ownScreenCount = ownScreenCount
        self.virtualScreenNamePrefix = virtualScreenNamePrefix
        self.virtualScreenFiles = virtualScreenFiles
        self.virtualScreenEvents = virtualScreenEvents
        self.playedAudioInputs = playedAudioInputs
        self.timeTolerance = timeTolerance
        self.finalizeAllowance = finalizeAllowance
        self.settleTime = settleTime
    }
}
