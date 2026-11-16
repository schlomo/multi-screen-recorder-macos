import Foundation

/// The detail lines of `--debug`, written to be read.
public enum DebugLine {
    /// "screen recording granted; microphone granted; screens: DELL P3421W 3440×1440 at (0,0) main, …"
    public static func facts(_ facts: ReadyCheckFacts) -> String {
        let screen = switch facts.screenRecording {
        case .granted: "granted"
        case .notGranted: "not granted"
        case .failed(let error): "failed (\(error))"
        }
        let microphone = facts.microphoneGranted.map { $0 ? "granted" : "not granted" } ?? "not asked"
        let screens = switch facts.screens {
        case .success(let screens): "screens: " + list(screens.map { screen in
            "\(screen.name) \(screen.sizeText) at (\(point(screen.originX)),\(point(screen.originY)))" + (screen.isMain ? " main" : "")
        })
        case .failure(let error): "screens cannot be read (\(error))"
        }
        let audioInputs = switch facts.audioInputs {
        case .success(let inputs): "audio inputs: " + list(inputs.map { "\($0.label) \($0.channelsText)" })
        case .failure(let error): "audio inputs cannot be read (\(error))"
        }
        let folder = switch facts.outputFolder {
        case .usable(.bytes(let bytes)): "output folder usable, \(DiskEstimate.gigabytes(Double(bytes))) free"
        case .usable(.unreadable(let error)): "output folder usable, free space cannot be read (\(error))"
        case .unusable(let error): "output folder unusable (\(error))"
        }
        return ["screen recording \(screen)", "microphone \(microphone)", screens, audioInputs, folder].joined(separator: "; ")
    }

    /// "start Screen 2 Wacom One 13T (UUID 037036FB…, display ID 2) at 1920×1080";
    /// `names` gives a stopped screen's "Screen <n> <name>".
    public static func action(_ action: ScreenTracker.Action, names: [String: String]) -> String {
        switch action {
        case .start(let uuid, let displayID, let frameSize, let number, let name):
            "start Screen \(number) \(name) (UUID \(uuid.prefix(8))…, display ID \(displayID)) at \(frameSize)"
        case .stop(let uuid, let ending):
            "stop \(names[uuid] ?? "screen \(uuid.prefix(8))…") (\(text(ending)))"
        }
    }

    /// "DELL P3421W 3440×1440 at (0,0) main (display ID 1), …"
    public static func screens(_ screens: [ConnectedScreen]) -> String {
        list(screens.map { screen in
            "\(screen.name ?? "unnamed") \(screen.pointSize) at (\(point(screen.bounds.x)),\(point(screen.bounds.y)))"
                + (screen.isMain ? " main" : "") + (screen.mirrorsUUID.map { " mirrors \($0)" } ?? "")
                + " (display ID \(screen.displayID))"
        })
    }

    private static func text(_ ending: ScreenTracker.Ending) -> String {
        switch ending {
        case .disconnected: "disconnected"
        case .frameSizeChanged: "frame size changed"
        case .mirroringStarted: "mirroring started"
        case .sleep: "sleep"
        case .stop: "stop"
        }
    }

    private static func list(_ items: [String]) -> String { items.isEmpty ? "none" : items.joined(separator: ", ") }

    private static func point(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
