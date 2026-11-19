import ColorSync
import CoreAudio
import CoreGraphics
import EndToEndLogic
import Foundation

/// The Mac's screens and audio devices as the restore file saves them.
enum Machine {
    /// The loopback device the tests play into: BlackHole's two-channel driver.
    static let loopbackUID = "BlackHole2ch_UID"
    static let loopbackName = "BlackHole 2ch"
    /// Aggregate devices the tests make carry this UID prefix.
    static let aggregatePrefix = "org.schapiro.multiscreenrecorder.end-to-end."

    /// The screens macOS lists, connected (`online`) or only those that are on, by their display IDs.
    static func screenIDs(online: Bool) -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        let status = online ? CGGetOnlineDisplayList(32, &ids, &count) : CGGetActiveDisplayList(32, &ids, &count)
        return status == .success ? Array(ids.prefix(Int(count))) : []
    }

    static func uuid(_ display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func isVirtualScreen(_ display: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(display) == VirtualScreenSpec.vendorID && CGDisplayModelNumber(display) == VirtualScreenSpec.productID
    }

    /// The tests' virtual screens that are connected now.
    static func virtualScreens() -> [CGDirectDisplayID] { screenIDs(online: true).filter(isVirtualScreen) }

    static func state() throws -> MachineState {
        let active = Set(screenIDs(online: false))
        let own = screenIDs(online: true).filter { !isVirtualScreen($0) }
        let screens = try own.map { display -> MachineState.Screen in
            guard let screenUUID = uuid(display) else { throw DriverError("screen \(display) has no UUID") }
            let mode = CGDisplayCopyDisplayMode(display)
            let bounds = CGDisplayBounds(display)
            let mirrored = CGDisplayMirrorsDisplay(display)
            return MachineState.Screen(
                uuid: screenUUID, active: active.contains(display), x: Int(bounds.origin.x), y: Int(bounds.origin.y),
                width: mode?.width ?? 0, height: mode?.height ?? 0, pixelWidth: mode?.pixelWidth ?? 0,
                pixelHeight: mode?.pixelHeight ?? 0, refreshRate: mode?.refreshRate ?? 0, modeID: mode?.ioDisplayModeID ?? 0,
                rotation: CGDisplayRotation(display),
                mirrorsUUID: mirrored == kCGNullDirectDisplay ? nil : uuid(mirrored))
        }
        let loopback = CoreAudioDevices.device(uid: loopbackUID).map { device in
            MachineState.LoopbackDevice(uid: loopbackUID, sampleRate: CoreAudioDevices.sampleRate(device) ?? 0,
                                        inputVolumes: CoreAudioDevices.inputVolumes(device))
        }
        return MachineState(
            screens: screens, mainScreenUUID: uuid(CGMainDisplayID()),
            defaultInputUID: CoreAudioDevices.defaultDevice(input: true).flatMap(CoreAudioDevices.uid),
            defaultOutputUID: CoreAudioDevices.defaultDevice(input: false).flatMap(CoreAudioDevices.uid),
            loopbackDevices: loopback.map { [$0] } ?? [])
    }

    /// The state as a process of its own reads it (`state`): this process
    /// keeps the screens' modes it read first, and would not see a change.
    static func freshState() throws -> MachineState {
        guard let executable = Bundle.main.executableURL else { throw DriverError("cannot find its own executable") }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["state"]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DriverError("state failed (exit \(process.terminationStatus))") }
        return try RestoreFile(json: data).saved
    }

    /// Carries out the plan's actions; what only the person can do is the caller's to tell.
    static func apply(_ plan: RestorePlan, saved: MachineState) throws {
        for action in plan.actions {
            switch action {
            case .arrangeScreens: try arrangeScreens(saved)
            case .defaultInput(let uid): try CoreAudioDevices.setDefaultDevice(input: true, uid: uid)
            case .defaultOutput(let uid): try CoreAudioDevices.setDefaultDevice(input: false, uid: uid)
            case .sampleRate(let uid, let rate):
                guard let device = CoreAudioDevices.device(uid: uid) else { throw DriverError("the audio device \(uid) is gone") }
                try CoreAudioDevices.setSampleRate(device, rate)
            case .inputVolume(let uid, let element, let volume):
                guard let device = CoreAudioDevices.device(uid: uid) else { throw DriverError("the audio device \(uid) is gone") }
                try CoreAudioDevices.setInputVolume(device, element: element, volume)
            }
        }
    }

    /// Every active screen back to its saved mode, position and mirroring, in one configuration.
    private static func arrangeScreens(_ saved: MachineState) throws {
        let byUUID = Dictionary(screenIDs(online: true).compactMap { display in uuid(display).map { ($0, display) } },
                                uniquingKeysWith: { first, _ in first })
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success, let configuration else {
            throw DriverError("macOS refused to begin a screen configuration")
        }
        for screen in saved.screens where screen.active {
            guard let display = byUUID[screen.uuid] else { continue }
            let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
            let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []
            guard let mode = modes.first(where: { $0.ioDisplayModeID == screen.modeID && $0.width == screen.width
                    && $0.height == screen.height && $0.pixelWidth == screen.pixelWidth }) else {
                CGCancelDisplayConfiguration(configuration)
                throw DriverError("screen \(screen.uuid) no longer offers its saved mode \(screen.width)×\(screen.height)")
            }
            let mirrors = screen.mirrorsUUID.flatMap { byUUID[$0] } ?? kCGNullDirectDisplay
            guard CGConfigureDisplayWithDisplayMode(configuration, display, mode, nil) == .success,
                  CGConfigureDisplayMirrorOfDisplay(configuration, display, mirrors) == .success,
                  mirrors != kCGNullDirectDisplay
                    || CGConfigureDisplayOrigin(configuration, display, Int32(screen.x), Int32(screen.y)) == .success
            else {
                CGCancelDisplayConfiguration(configuration)
                throw DriverError("macOS refused the saved arrangement of screen \(screen.uuid)")
            }
        }
        guard CGCompleteDisplayConfiguration(configuration, .permanently) == .success else {
            throw DriverError("macOS refused to apply the saved screen arrangement")
        }
    }

    /// Removes aggregate devices that carry the tests' UID prefix: one may
    /// outlive the process that made it.
    static func removeTestAggregateDevices() throws -> [String] {
        try CoreAudioDevices.all().compactMap { device in
            guard CoreAudioDevices.isAggregate(device), let uid = CoreAudioDevices.uid(device), uid.hasPrefix(aggregatePrefix)
            else { return nil }
            try CoreAudioDevices.check(AudioHardwareDestroyAggregateDevice(device), "remove the aggregate device \(uid)")
            return uid
        }
    }
}
