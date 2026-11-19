import CoreGraphics
import EndToEndLogic
import Foundation
import VirtualScreen

/// The device helper's virtual screen in a process of its own, a subcommand
/// of this executable: ending the process removes the screen. It ends on
/// SIGTERM, SIGINT or when its standard input closes, which happens when the
/// driver that started it ends in any way. A line `size <width>x<height>`
/// on its standard input switches the screen's mode.
enum VirtualScreenHelper {
    static let readyPrefix = "connected "
    static let switchedPrefix = "switched "
    static let failedPrefix = "failed "
    static let startSwitchDelay = 1.0

    /// The helper process's body: makes the screen, says so, and holds it.
    static func hold(_ spec: VirtualScreenSpec) throws -> Never {
        guard MSRVirtualScreen.isAvailable else {
            throw DriverError("this macOS has no CGVirtualDisplay, the private interface virtual screens need")
        }
        guard let screen = MSRVirtualScreen(
            name: spec.name, vendorID: VirtualScreenSpec.vendorID, productID: VirtualScreenSpec.productID,
            serialNumber: spec.serialNumber,
            sizes: spec.sizes.map { NSValue(size: CGSize(width: $0.width, height: $0.height)) })
        else {
            throw DriverError("macOS refused the virtual screen \(spec.name) (\(spec.sizes))")
        }
        let display = screen.displayID
        let first = spec.sizes[0]
        try waitUntilActive(display, seconds: 5)
        // macOS keeps the last mode switched to for each identity and brings
        // a screen back at it; the helper puts it back to its first size at
        // its start and its end, so the next screen of that identity starts
        // there. At the start only after a while: a switch right after the
        // screen appears is undone as macOS applies the kept mode (tried
        // 2026-11-19).
        let bounds = CGDisplayBounds(display)
        if Int(bounds.width) != first.width || Int(bounds.height) != first.height {
            Thread.sleep(forTimeInterval: startSwitchDelay)
            try switchModeInOwnProcess(display, to: first)
        }
        let leaving = DispatchQueue(label: "leaving")
        let signals = [SIGTERM, SIGINT].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: leaving)
            source.setEventHandler { leave(display, at: first) }
            source.resume()
            return source
        }
        print("\(readyPrefix)\(display)")
        fflush(stdout)
        while let line = readLine() {
            guard line.hasPrefix("size "), let size = ScreenSize(String(line.dropFirst("size ".count))) else { continue }
            do {
                try switchModeInOwnProcess(display, to: size)
                print("\(switchedPrefix)\(size)")
            } catch {
                print("\(failedPrefix)\(error)")
            }
            fflush(stdout)
        }
        withExtendedLifetime((screen, signals)) { leave(display, at: first) }
    }

    /// Back to its first size, then the process ends and the screen with it.
    private static func leave(_ display: CGDirectDisplayID, at first: ScreenSize) -> Never {
        do {
            try switchModeInOwnProcess(display, to: first)
        } catch {
            print("\(failedPrefix)\(error)")
            exit(1)
        }
        exit(0)
    }

    static func waitUntilActive(_ display: CGDirectDisplayID, seconds: Double) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !Machine.screenIDs(online: false).contains(display) {
            guard Date() < deadline else { throw DriverError("the virtual screen \(display) did not become active within \(Int(seconds)) s") }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// Starts a helper and waits until its screen is active; returns the
    /// process and the screen's UUID.
    static func connect(_ spec: VirtualScreenSpec, executable: String, folder: URL) throws -> (ChildProcess, String) {
        let process = try ChildProcess(
            executable: executable,
            arguments: ["virtual-screen", "--serial-number", "\(spec.serialNumber)"]
                + spec.sizes.flatMap { ["--size", "\($0)"] },
            environment: ProcessInfo.processInfo.environment,
            standardOutput: folder.appending(path: "virtual-screen-\(spec.serialNumber).out"),
            standardError: folder.appending(path: "virtual-screen-\(spec.serialNumber).err"), lifeline: true)
        let deadline = Date().addingTimeInterval(10)
        while true {
            if let line = process.output().split(separator: "\n").first(where: { $0.hasPrefix(readyPrefix) }),
               let display = CGDirectDisplayID(line.dropFirst(readyPrefix.count)) {
                guard let uuid = Machine.uuid(display) else { throw DriverError("the virtual screen \(display) has no UUID") }
                return (process, uuid)
            }
            if process.hasExited || Date() > deadline {
                process.signal(SIGKILL)
                _ = process.wait(seconds: 5)
                throw DriverError("the virtual screen \(spec.name) did not connect: \(process.errors())")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// Waits until the screen is active at the size; macOS keeps a mode per
    /// identity, so another size means that identity was used at it before.
    static func waitFor(_ display: CGDirectDisplayID, toBe size: ScreenSize, seconds: Double) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            let bounds = CGDisplayBounds(display)
            if Machine.screenIDs(online: false).contains(display), Int(bounds.width) == size.width, Int(bounds.height) == size.height {
                return
            }
            guard Date() < deadline else {
                throw DriverError("the virtual screen \(display) is not active at \(size) within \(Int(seconds)) s, but \(Int(bounds.width))x\(Int(bounds.height))")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// Runs `switch-mode` for the screen and waits for it: a process that
    /// read a screen's modes keeps what it read, and one that read them
    /// right after the screen connected switches to none of them (tried
    /// 2026-11-19), so every switch is a fresh process.
    static func switchModeInOwnProcess(_ display: CGDirectDisplayID, to size: ScreenSize) throws {
        guard let uuid = Machine.uuid(display) else { throw DriverError("the virtual screen \(display) has no UUID") }
        guard let executable = Bundle.main.executableURL else { throw DriverError("cannot find its own executable") }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["switch-mode", "--screen-uuid", uuid, "--size", "\(size)"]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw DriverError("switch-mode to \(size) failed (exit \(process.terminationStatus))") }
    }

    /// Switches the screen's mode through the public interface, for the
    /// login session, and waits until it shows.
    static func switchMode(uuid: String, to size: ScreenSize) throws {
        guard let display = Machine.screenIDs(online: true).first(where: { Machine.uuid($0) == uuid }) else {
            throw DriverError("the virtual screen \(uuid) is gone")
        }
        let bounds = CGDisplayBounds(display)
        if Int(bounds.width) == size.width, Int(bounds.height) == size.height { return }
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []
        // The mode drawn at that size (1x) and usable for the desktop: macOS lists some sizes twice.
        guard let mode = modes.first(where: { $0.width == size.width && $0.height == size.height
            && $0.pixelWidth == size.width && $0.pixelHeight == size.height && $0.isUsableForDesktopGUI() }) else {
            throw DriverError("the virtual screen \(uuid) has no mode \(size): \(modes.map { "\($0.width)x\($0.height)" })")
        }
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success, let configuration else {
            throw DriverError("macOS refused to begin a screen configuration")
        }
        guard CGConfigureDisplayWithDisplayMode(configuration, display, mode, nil) == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw DriverError("macOS refused the mode \(size) for the virtual screen \(uuid)")
        }
        guard CGCompleteDisplayConfiguration(configuration, .forSession) == .success else {
            throw DriverError("macOS refused to switch the virtual screen \(uuid) to \(size)")
        }
        try waitFor(display, toBe: size, seconds: 5)
    }

    /// Asks the helper to switch its screen's mode and waits until it has.
    static func requestModeSwitch(_ process: ChildProcess, to size: ScreenSize) throws {
        let before = process.output()
        try process.send("size \(size)\n")
        let deadline = Date().addingTimeInterval(10)
        while true {
            let new = process.output().dropFirst(before.count)
            if new.contains("\(switchedPrefix)\(size)\n") { return }
            if new.contains(failedPrefix) || process.hasExited || Date() > deadline {
                throw DriverError("the virtual screen was not switched to \(size): \(new) \(process.errors())")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// Ends a helper and waits until macOS no longer lists its screen.
    static func disconnect(_ process: ChildProcess, uuid: String) throws {
        process.signal(SIGTERM)
        guard process.wait(seconds: 5) else {
            process.signal(SIGKILL)
            _ = process.wait(seconds: 5)
            throw DriverError("the virtual screen helper \(process.pid) did not end on SIGTERM")
        }
        let deadline = Date().addingTimeInterval(5)
        while Machine.screenIDs(online: true).contains(where: { Machine.uuid($0) == uuid }) {
            guard Date() < deadline else { throw DriverError("the virtual screen \(uuid) is still connected 5 s after its helper ended") }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    static func waitUntilNoVirtualScreen(seconds: Double) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !Machine.virtualScreens().isEmpty {
            guard Date() < deadline else {
                throw DriverError("a virtual screen of the tests is still connected after \(Int(seconds)) s: \(Machine.virtualScreens())")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
}
