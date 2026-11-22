import Foundation

/// A change the driver made during a recording: when it asked for it and
/// when it saw it done, in seconds after the recording's start.
public struct ChangeTimes: Sendable, Equatable {
    public var asked: Double
    public var done: Double
    /// The changed screen's last change after the ask, as the driver
    /// watched it (`ScreenSettling`); nil when not watched.
    public var lastChange: Double?
    /// When the recorder noticed the change, by the event it writes for it
    /// (`screen connected`), once that event has passed its own check; nil
    /// when it writes none.
    public var notice: Double?

    public init(asked: Double, done: Double, lastChange: Double? = nil) {
        self.asked = asked
        self.done = done
        self.lastChange = lastChange
    }

    /// What a settled time follows: the later of the recorder's notice and
    /// the screen's last change.
    public struct Anchor: Sendable, Equatable {
        public enum Source: Sendable, Equatable {
            case notice, lastChange

            public var description: String { self == .notice ? "the recorder's notice" : "the screen's last change" }
        }

        public var time: Double
        public var source: Source
    }

    public var anchor: Anchor? {
        let candidates = [notice.map { Anchor(time: $0, source: .notice) }, lastChange.map { Anchor(time: $0, source: .lastChange) }]
        return candidates.compactMap(\.self).max { $0.time < $1.time }
    }

    /// Where a time the recorder writes for the change may lie, by its kind,
    /// widened by the tolerance: an immediate one from the ask to the done;
    /// a settled one the settle time after its anchor (when not watched,
    /// from the ask to the done, the settle time later); a file's start
    /// as a settled one, but up to the first-frame limit late.
    public func window(_ kind: TimingKind, settleTime: Double, tolerance: Double, firstFrameLimit: Double) -> ClosedRange<Double> {
        let late = kind == .started ? firstFrameLimit : tolerance
        return switch kind {
        case .immediate: (asked - tolerance)...(done + tolerance)
        case .settled, .started:
            if let anchor { (anchor.time + settleTime - tolerance)...(anchor.time + settleTime + late) }
            else { (asked + settleTime - tolerance)...(done + settleTime + late) }
        }
    }

    public func windowWidth(_ kind: TimingKind, settleTime: Double, tolerance: Double, firstFrameLimit: Double) -> Double {
        let window = window(kind, settleTime: settleTime, tolerance: tolerance, firstFrameLimit: firstFrameLimit)
        return window.upperBound - window.lowerBound
    }
}

/// How a time the recorder writes follows the change it tells of.
public enum TimingKind: Sendable, Equatable {
    /// After the settle time: `screen frame size changed`, a file's end at
    /// a mode switch.
    case settled
    /// A screen file's start: after the settle time, its first frame
    /// within the first-frame limit.
    case started
    /// With the change: `screen connected`, `screen disconnected`, a file's
    /// end at a disconnect.
    case immediate

    var description: String { self == .immediate ? "with the change" : "the settle time after the change" }
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
        /// The VM has no camera, so a scenario keeps the default camera mode and no camera file is expected.
        public var cameraMode: String

        public init(resolution: String, audioMode: String, systemAudio: Bool, cameraMode: String = "real") {
            self.resolution = resolution
            self.audioMode = audioMode
            self.systemAudio = systemAudio
            self.cameraMode = cameraMode
        }

        var json: JSONValue {
            .object(["resolution": .string(resolution), "audioMode": .string(audioMode), "systemAudio": .bool(systemAudio),
                     "cameraMode": .string(cameraMode)])
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
        /// The index, among the virtual screens' events, of the recorder's
        /// notice of `startedBy` (a connect's `screen connected`); nil for a
        /// mode switch, whose event the recorder writes only at the settle.
        public var noticedBy: Int?
        /// The mode switch (settled) or disconnect (immediate) that ends it;
        /// nil when the recording ended first.
        public var endedBy: ExpectedTime?

        public init(screenUUID: String, frameSize: [Int], startedBy: ChangeTimes, noticedBy: Int?, endedBy: ExpectedTime?) {
            self.screenUUID = screenUUID
            self.frameSize = frameSize
            self.startedBy = startedBy
            self.noticedBy = noticedBy
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
    /// The names of the virtual screens; macOS may append a counter, so a name matches by its start.
    public var virtualScreenNames: [String]
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
    /// How long after the settle time a screen file may start.
    public var firstFrameLimit: Double

    public init(
        app: String, settings: Settings, ending: Ending, stoppedAt: Double, ownScreenCount: Int,
        virtualScreenNames: [String], virtualScreenFiles: [VirtualScreenFile] = [],
        virtualScreenEvents: [VirtualScreenEvent] = [], playedAudioInputs: [PlayedAudioInput] = [],
        timeTolerance: Double, finalizeAllowance: Double, settleTime: Double, firstFrameLimit: Double
    ) {
        self.firstFrameLimit = firstFrameLimit
        self.app = app
        self.settings = settings
        self.ending = ending
        self.stoppedAt = stoppedAt
        self.ownScreenCount = ownScreenCount
        self.virtualScreenNames = virtualScreenNames
        self.virtualScreenFiles = virtualScreenFiles
        self.virtualScreenEvents = virtualScreenEvents
        self.playedAudioInputs = playedAudioInputs
        self.timeTolerance = timeTolerance
        self.finalizeAllowance = finalizeAllowance
        self.settleTime = settleTime
    }

    public func isVirtualScreenName(_ name: String) -> Bool {
        virtualScreenNames.contains { name.hasPrefix($0) }
    }
}
