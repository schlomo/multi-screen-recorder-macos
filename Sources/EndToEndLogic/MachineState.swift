import Foundation

/// What an end-to-end run may change on the Mac, saved in the restore file
/// before the run and put back after it (docs/design/end-to-end-tests.md,
/// "Safeguards for the person's session"). The time and the time zone are
/// not in it: no scenario set changes them yet.
public struct MachineState: Codable, Equatable, Sendable {
    /// One of the Mac's own screens, known by its UUID.
    public struct Screen: Codable, Equatable, Sendable {
        public var uuid: String
        /// Whether it is on: active, not only connected.
        public var active: Bool
        public var x: Int
        public var y: Int
        /// The mode: its looks-like size, the size it is drawn at, its
        /// refresh rate and macOS's own number for it.
        public var width: Int
        public var height: Int
        public var pixelWidth: Int
        public var pixelHeight: Int
        public var refreshRate: Double
        public var modeID: Int32
        public var rotation: Double
        /// The screen it mirrors, if it mirrors one.
        public var mirrorsUUID: String?

        public init(uuid: String, active: Bool, x: Int, y: Int, width: Int, height: Int, pixelWidth: Int,
                    pixelHeight: Int, refreshRate: Double, modeID: Int32, rotation: Double, mirrorsUUID: String?) {
            self.uuid = uuid
            self.active = active
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.refreshRate = refreshRate
            self.modeID = modeID
            self.rotation = rotation
            self.mirrorsUUID = mirrorsUUID
        }

        var arrangement: [String] {
            ["\(x),\(y)", "\(width)×\(height)", "drawn at \(pixelWidth)×\(pixelHeight)", "\(refreshRate) Hz",
             "mode \(modeID)", "mirrors \(mirrorsUUID ?? "none")"]
        }
    }

    /// A loopback device the tests play into (BlackHole).
    public struct LoopbackDevice: Codable, Equatable, Sendable {
        public var uid: String
        public var sampleRate: Double
        /// The input volume of each channel element from 0 (the main
        /// element), nil where the device has none.
        public var inputVolumes: [Float?]

        public init(uid: String, sampleRate: Double, inputVolumes: [Float?]) {
            self.uid = uid
            self.sampleRate = sampleRate
            self.inputVolumes = inputVolumes
        }
    }

    /// The Mac's own screens, connected ones included, by UUID.
    public var screens: [Screen]
    public var mainScreenUUID: String?
    public var defaultInputUID: String?
    public var defaultOutputUID: String?
    public var loopbackDevices: [LoopbackDevice]

    public init(screens: [Screen], mainScreenUUID: String?, defaultInputUID: String?, defaultOutputUID: String?,
                loopbackDevices: [LoopbackDevice]) {
        self.screens = screens.sorted { $0.uuid < $1.uuid }
        self.mainScreenUUID = mainScreenUUID
        self.defaultInputUID = defaultInputUID
        self.defaultOutputUID = defaultOutputUID
        self.loopbackDevices = loopbackDevices.sorted { $0.uid < $1.uid }
    }

    /// Every way `current` differs from this saved state, one line each.
    public func differences(to current: MachineState) -> [String] {
        var lines: [String] = []
        let now = Dictionary(current.screens.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        for screen in screens {
            guard let other = now[screen.uuid] else {
                lines.append("screen \(screen.uuid) is gone")
                continue
            }
            if other.active != screen.active { lines.append("screen \(screen.uuid) is \(other.active ? "on" : "off"), was \(screen.active ? "on" : "off")") }
            if other.arrangement != screen.arrangement {
                lines.append("screen \(screen.uuid) is \(other.arrangement.joined(separator: ", ")), was \(screen.arrangement.joined(separator: ", "))")
            }
            if other.rotation != screen.rotation { lines.append("screen \(screen.uuid) is rotated \(other.rotation)°, was \(screen.rotation)°") }
        }
        for extra in current.screens.map(\.uuid) where !screens.contains(where: { $0.uuid == extra }) {
            lines.append("screen \(extra) is new")
        }
        if current.mainScreenUUID != mainScreenUUID {
            lines.append("the main screen is \(current.mainScreenUUID ?? "none"), was \(mainScreenUUID ?? "none")")
        }
        if current.defaultInputUID != defaultInputUID {
            lines.append("the default microphone is \(current.defaultInputUID ?? "none"), was \(defaultInputUID ?? "none")")
        }
        if current.defaultOutputUID != defaultOutputUID {
            lines.append("the default output is \(current.defaultOutputUID ?? "none"), was \(defaultOutputUID ?? "none")")
        }
        if current.loopbackDevices != loopbackDevices {
            lines.append("the loopback devices are \(current.loopbackDevices), were \(loopbackDevices)")
        }
        return lines
    }
}

/// What restoring a saved state takes, from the state found now.
public struct RestorePlan: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Put every screen back to its saved position, mode and mirroring,
        /// and the main screen with them (macOS sets these together).
        case arrangeScreens
        case defaultInput(uid: String)
        case defaultOutput(uid: String)
        case sampleRate(uid: String, rate: Double)
        case inputVolume(uid: String, element: Int, volume: Float)
    }

    public var actions: [Action] = []
    /// What only the person can put back, one line each.
    public var forThePerson: [String] = []

    public init(saved: MachineState, current: MachineState) {
        let now = Dictionary(current.screens.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        var arrange = current.mainScreenUUID != saved.mainScreenUUID
        for screen in saved.screens {
            guard let other = now[screen.uuid] else {
                forThePerson.append("screen \(screen.uuid) is gone: connect it again")
                continue
            }
            if other.active != screen.active {
                forThePerson.append("screen \(screen.uuid) is \(other.active ? "on" : "off"): switch it \(screen.active ? "on" : "off")")
            }
            if other.rotation != screen.rotation {
                forThePerson.append("screen \(screen.uuid) is rotated \(other.rotation)°: set it to \(screen.rotation)° in System Settings")
            }
            if screen.active, other.active, other.arrangement != screen.arrangement { arrange = true }
        }
        if arrange { actions.append(.arrangeScreens) }
        if let uid = saved.defaultInputUID, current.defaultInputUID != uid { actions.append(.defaultInput(uid: uid)) }
        if let uid = saved.defaultOutputUID, current.defaultOutputUID != uid { actions.append(.defaultOutput(uid: uid)) }
        let devices = Dictionary(current.loopbackDevices.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        for device in saved.loopbackDevices {
            guard let other = devices[device.uid] else {
                forThePerson.append("the loopback device \(device.uid) is gone")
                continue
            }
            if other.sampleRate != device.sampleRate { actions.append(.sampleRate(uid: device.uid, rate: device.sampleRate)) }
            for (element, volume) in device.inputVolumes.enumerated() {
                guard let volume, element < other.inputVolumes.count, other.inputVolumes[element] != volume else { continue }
                actions.append(.inputVolume(uid: device.uid, element: element, volume: volume))
            }
        }
    }
}

/// The restore file: the state saved before a run and the processes the
/// run started, so `restore` can end them should the driver itself die.
public struct RestoreFile: Codable, Equatable, Sendable {
    public struct StartedProcess: Codable, Equatable, Sendable {
        public var pid: Int32
        /// The executable's path, so `restore` never signals another
        /// process that got the same number.
        public var executable: String
        /// The signal that ends it as intended: SIGINT finalizes a recording.
        public var stopSignal: Int32

        public init(pid: Int32, executable: String, stopSignal: Int32) {
            self.pid = pid
            self.executable = executable
            self.stopSignal = stopSignal
        }
    }

    public var saved: MachineState
    public var processes: [StartedProcess]

    public init(saved: MachineState, processes: [StartedProcess] = []) {
        self.saved = saved
        self.processes = processes
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public init(json data: Data) throws {
        self = try JSONDecoder().decode(RestoreFile.self, from: data)
    }
}
