import Foundation

/// A width and height in points.
public struct ScreenSize: Sendable, Equatable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// "1280x720", as the device helper's command line takes it.
    public init?(_ text: String) {
        guard let match = text.wholeMatch(of: /(\d+)x(\d+)/), let width = Int(match.1), let height = Int(match.2),
              width > 0, height > 0 else { return nil }
        self.init(width: width, height: height)
    }

    public var description: String { "\(width)x\(height)" }
}

/// A virtual screen the device helper makes: its identity (the tests'
/// vendor and product with this serial number, so macOS gives it the same
/// UUID every time) and its modes, at 1x: the size it looks like first,
/// and the sizes it can be switched to. macOS keeps a mode per identity
/// (tried 2026-11-19): a screen made again with the same identity comes
/// back at the size it first had, whatever its modes, so a size change is a
/// mode switch, never a replacement.
public struct VirtualScreenSpec: Sendable, Equatable {
    /// The tests' identities: macOS keeps an arrangement and a colour
    /// profile per identity, so they are few and fixed.
    public static let vendorID: UInt32 = 0x4D53
    public static let productID: UInt32 = 0x5254
    public static let namePrefix = "MSR Test"

    public var serialNumber: UInt32
    /// Its modes; it starts at the first.
    public var sizes: [ScreenSize]

    public init(serialNumber: UInt32, sizes: [ScreenSize]) {
        self.serialNumber = serialNumber
        self.sizes = sizes
    }

    public var name: String { "\(Self.namePrefix) \(serialNumber)" }
}

/// A named scenario: a recording, timed events while it runs, how it stops,
/// and the assertions that follow (docs/design/end-to-end-tests.md).
public struct Scenario: Sendable {
    public enum Event: Sendable, Equatable {
        case connectScreen(VirtualScreenSpec)
        /// A mode switch through the public interface, to one of its sizes.
        case switchScreenMode(serialNumber: UInt32, to: ScreenSize)
        case disconnectScreen(serialNumber: UInt32)
    }

    public enum Stop: Sendable, Equatable {
        /// `msr record --duration` ends it.
        case duration
        /// SIGINT, as Ctrl-C in a terminal.
        case interrupt
        /// `kill -9`.
        case kill
    }

    public var name: String
    public var summary: String
    /// `msr record`'s flags besides `--output-folder` and `--duration`.
    public var flags: [String]
    /// The settings the manifest must name for these flags.
    public var settings: ManifestExpectation.Settings
    /// Whether the driver plays the test tone into the loopback device.
    public var playsTone: Bool
    /// The events, at seconds after the recording started.
    public var events: [(at: Double, event: Event)]
    public var stop: Stop
    /// When it stops, in seconds after the recording started.
    public var stopAt: Double

    public init(name: String, summary: String, flags: [String], settings: ManifestExpectation.Settings,
                playsTone: Bool = false, events: [(at: Double, event: Event)] = [], stop: Stop, stopAt: Double) {
        self.name = name
        self.summary = summary
        self.flags = flags
        self.settings = settings
        self.playsTone = playsTone
        self.events = events
        self.stop = stop
        self.stopAt = stopAt
    }

    /// How long after its stop a recording stopped by a signal ends by its
    /// own `--duration`, should the driver have been killed before sending it.
    public static let ceilingMargin = 120.0

    /// `msr record`'s arguments: every recording has a duration, the stop
    /// itself or a ceiling past the stop.
    public func arguments(outputFolder: String) -> [String] {
        let duration = stop == .duration ? stopAt : stopAt + Self.ceilingMargin
        return ["record", "--output-folder", outputFolder] + flags + ["--duration", "\(Int(duration))s"]
    }
}

extension Scenario {
    static let auto = ManifestExpectation.Settings(resolution: "native", audioMode: "wired", systemAudio: true)
    static let screen = VirtualScreenSpec(
        serialNumber: 101, sizes: [ScreenSize(width: 1280, height: 720), ScreenSize(width: 1600, height: 900)])
    /// How often the stress scenario switches the screen's mode.
    static let stressSwitches = 10
    static let fixedFlags = ["--resolution", "1080p", "--audio-mode", "all-inputs"]

    /// The stress scenario: its events built step by step, so no type inference has to solve them at once.
    static let stress: Scenario = {
        let firstSwitch: Double = 5
        let switchSpacing: Double = 2
        var events: [(at: Double, event: Event)] = [(at: 2, event: .connectScreen(screen))]
        for index in 0..<stressSwitches {
            let at: Double = firstSwitch + Double(index) * switchSpacing
            let size: ScreenSize = screen.sizes[(index + 1) % 2]
            events.append((at: at, event: .switchScreenMode(serialNumber: screen.serialNumber, to: size)))
        }
        let lastSwitch: Double = firstSwitch + Double(stressSwitches - 1) * switchSpacing
        events.append((at: lastSwitch + 3, event: .disconnectScreen(serialNumber: screen.serialNumber)))
        return Scenario(
            name: "virtual-screen-stress",
            summary: "a virtual screen connected, its mode switched ten times about 2 s apart, and disconnected",
            flags: fixedFlags + ["--system-audio", "off", "--debug"],
            settings: .init(resolution: "1080p", audioMode: "all-inputs", systemAudio: false),
            events: events, stop: .interrupt, stopAt: lastSwitch + 6)
    }()

    /// The named scenarios, the regression suite, in the order they run.
    public static let named: [Scenario] = [
        Scenario(
            name: "plain-recording", summary: "a recording in auto mode, ended by its duration",
            flags: [], settings: auto, stop: .duration, stopAt: 8),
        Scenario(
            name: "virtual-screen",
            summary: "a virtual screen connected, its mode switched there and back, and disconnected",
            flags: fixedFlags + ["--system-audio", "off", "--debug"],
            settings: .init(resolution: "1080p", audioMode: "all-inputs", systemAudio: false),
            events: [
                (2, .connectScreen(screen)),
                (6, .switchScreenMode(serialNumber: screen.serialNumber, to: screen.sizes[1])),
                (10, .switchScreenMode(serialNumber: screen.serialNumber, to: screen.sizes[0])),
                (14, .disconnectScreen(serialNumber: screen.serialNumber)),
            ],
            stop: .interrupt, stopAt: 17),
        stress,
        Scenario(
            name: "tone", summary: "the test tone in the loopback device: level, silent stretches, timing by timecode",
            flags: fixedFlags + ["--system-audio", "off"],
            settings: .init(resolution: "1080p", audioMode: "all-inputs", systemAudio: false),
            playsTone: true, stop: .interrupt, stopAt: 10),
        Scenario(
            name: "system-audio", summary: "the system audio recorded beside the test tone",
            flags: fixedFlags + ["--system-audio", "on"],
            settings: .init(resolution: "1080p", audioMode: "all-inputs", systemAudio: true),
            playsTone: true, stop: .interrupt, stopAt: 10),
        Scenario(
            name: "stop-by-ctrl-c", summary: "Ctrl-C (SIGINT) finalizes the recording",
            flags: [], settings: auto, stop: .interrupt, stopAt: 6),
        Scenario(
            name: "stop-by-kill", summary: "kill -9 leaves every file readable up to its last fragment",
            flags: [], settings: auto, stop: .kill, stopAt: 7),
    ]
}

/// An event as it happened: when the driver asked for it and when it saw
/// it done, in seconds after the recording started, and for a virtual
/// screen its UUID.
public struct HappenedEvent: Sendable, Equatable {
    public var times: ChangeTimes
    public var event: Scenario.Event
    public var screenUUID: String?

    public init(times: ChangeTimes, event: Scenario.Event, screenUUID: String? = nil) {
        self.times = times
        self.event = event
        self.screenUUID = screenUUID
    }
}

extension Scenario {
    /// The virtual screens' files and events the manifest must list, from
    /// what happened, each tied to the change that brings it. A connected
    /// screen's file starts after the settle time; at a mode switch the
    /// screen's file ends and one at the new frame size starts after the
    /// settle time, when `screen frame size changed` is written (recorder.md,
    /// "Screen identity" and the screen tracker).
    public static func virtualScreenExpectation(_ happened: [HappenedEvent])
        -> (files: [ManifestExpectation.VirtualScreenFile], events: [ManifestExpectation.VirtualScreenEvent])
    {
        var files: [ManifestExpectation.VirtualScreenFile] = []
        var events: [ManifestExpectation.VirtualScreenEvent] = []
        var open: [UInt32: Int] = [:]
        for event in happened {
            switch event.event {
            case .connectScreen(let spec):
                open[spec.serialNumber] = files.count
                files.append(.init(screenUUID: event.screenUUID ?? "?", frameSize: [spec.sizes[0].width, spec.sizes[0].height],
                                   startedBy: event.times, noticedBy: events.count, endedBy: nil))
                events.append(.init(event: "screen connected", expected: .init(change: event.times, kind: .immediate)))
            case .switchScreenMode(let serialNumber, let size):
                guard let index = open[serialNumber] else { continue }
                files[index].endedBy = .init(change: event.times, kind: .settled)
                open[serialNumber] = files.count
                files.append(.init(screenUUID: files[index].screenUUID, frameSize: [size.width, size.height],
                                   startedBy: event.times, noticedBy: nil, endedBy: nil))
                events.append(.init(event: "screen frame size changed", expected: .init(change: event.times, kind: .settled)))
            case .disconnectScreen(let serialNumber):
                if let index = open.removeValue(forKey: serialNumber) {
                    files[index].endedBy = .init(change: event.times, kind: .immediate)
                }
                events.append(.init(event: "screen disconnected", expected: .init(change: event.times, kind: .immediate)))
            }
        }
        return (files, events)
    }
}
