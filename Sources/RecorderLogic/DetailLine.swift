import Foundation

/// The detail lines, written to be read: always in the recording log, and
/// with `--debug` also on standard error (D64).
public enum DetailLine {
    /// A detail line before its time and prefix are added.
    public struct Entry: Equatable, Sendable {
        public var category: String
        public var message: String

        public init(category: String, message: String) {
            self.category = category
            self.message = message
        }
    }

    /// A detail line on standard error, with the time since the start
    /// as an event line has it while a recording runs: "detail recorder:
    /// +27.9s start Screen 3 - LG".
    public static func standardErrorText(_ message: String, category: String, seconds: Double?) -> String {
        "detail \(category): " + (seconds.map { EventLine.elapsed($0) + " " } ?? "") + message
    }

    /// A detail line as the recording log has it, after the local time and
    /// the time since the start: "22:14:58 +27.9s detail recorder: start
    /// Screen 3 - LG".
    public static func recordingLogText(
        _ message: String, category: String, seconds: Double, started: Date, timeZone: TimeZone
    ) -> String {
        EventLine.time(seconds, started: started, timeZone: timeZone) + " detail \(category): " + message
    }

    /// "screen recording granted; microphone granted; screens: DELL P3421W 3440×1440 at (0,0) main, …"
    public static func facts(_ facts: ReadyCheckFacts) -> String {
        let screen = switch facts.screenRecording {
        case .granted: "granted"
        case .notGranted: "not granted"
        case .failed(let error): "failed (\(error))"
        case nil: "not asked"
        }
        let microphone = facts.microphoneGranted.map { $0 ? "granted" : "not granted" } ?? "not asked"
        let camera = facts.cameraGranted.map { $0 ? "granted" : "not granted" } ?? "not asked"
        let screens = switch facts.screens {
        case .success(let screens): "screens: " + list(screens.map { screen in
            "\(screen.name) \(screen.sizeText) at (\(point(screen.originX)),\(point(screen.originY)))" + (screen.isMain ? " main" : "")
        })
        case .failure(let error): "screens cannot be read (\(ErrorDetail(error).text))"
        }
        let audioInputs = switch facts.audioInputs {
        case .success(let inputs): "audio inputs: " + list(inputs.map { "\($0.shownName) \($0.channelsText)" })
        case .failure(let error): "audio inputs cannot be read (\(ErrorDetail(error).text))"
        }
        let folder = switch facts.outputFolder {
        case .usable(.bytes(let bytes)): "output folder usable, \(DiskEstimate.gigabytes(Double(bytes))) free"
        case .usable(.unreadable(let error)): "output folder usable, free space cannot be read (\(error))"
        case .unusable(let error): "output folder unusable (\(error))"
        }
        let cameras = "cameras: " + Self.cameras(facts.cameras)
        return ["screen recording \(screen)", "microphone \(microphone)", "camera \(camera)", screens, audioInputs, cameras, folder]
            .joined(separator: "; ")
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

    /// "start Camera 1 FaceTime HD Camera (unique ID 0x14100…) in 1920×1080 at 30 fps at 1920×1080";
    /// `names` gives a stopped camera's "Camera <n> <name>".
    public static func cameraAction(_ action: CameraTracker.Action, names: [String: String]) -> String {
        switch action {
        case .start(let uniqueID, let format, let frameSize, let number, let name):
            "start Camera \(number) \(name) (unique ID \(uniqueID.prefix(8))…) in \(format) at \(frameSize)"
        case .stop(let uniqueID):
            "stop \(names[uniqueID] ?? "camera \(uniqueID.prefix(8))…")"
        }
    }

    /// "FaceTime HD Camera (default) 1920×1080 at 30 fps, OBS Virtual Camera virtual 1280×720 at 30 fps"
    public static func cameras(_ cameras: [CameraInfo]) -> String {
        list(cameras.map { camera in
            camera.shownName + (camera.isVirtual ? " virtual" : "") + (camera.isSuspended ? " suspended" : "") + (camera.chosenFormat.map { " \($0)" } ?? " no format")
        })
    }

    /// "DELL P3421W 3440×1440 at (0,0) main (display ID 1), …"
    public static func screens(_ screens: [ConnectedScreen]) -> String {
        list(screens.map { screen in
            "\(screen.name ?? "unnamed") \(screen.pointSize) at (\(point(screen.bounds.x)),\(point(screen.bounds.y)))"
                + (screen.isMain ? " main" : "") + (screen.mirrorsUUID.map { " mirrors \($0)" } ?? "")
                + " (display ID \(screen.displayID))"
        })
    }

    /// "Audio 1 - Razer Seiren V3 Mini: clock drift -116.1 ppm, corrected +34.94 ms so far, 0.04 ms off";
    /// "clock drift not measured yet" until it is, and no "off" before the first estimate.
    public static func clockDrift(of label: String, _ status: ClockDriftCorrection.Status) -> String {
        let drift = status.clockDriftPpm.map { "clock drift " + ClockDriftText.signed($0, decimals: 1, unit: "ppm") }
            ?? "clock drift not measured yet"
        var line = "\(label): \(drift), corrected \(ClockDriftText.signed(status.applied * 1000, decimals: 2, unit: "ms")) so far"
        if let remaining = status.remaining { line += ", \(ClockDriftText.size(remaining * 1000, decimals: 2, unit: "ms")) off" }
        return line
    }

    /// The clock drift lines of all audio sources being recorded, as one block in number order,
    /// the system audio (0) first.
    public static func clockDriftBlock(_ sources: [(number: Int, label: String, status: ClockDriftCorrection.Status)]) -> [String] {
        sources.sorted { $0.number < $1.number }.map { clockDrift(of: $0.label, $0.status) }
    }

    /// "Audio 1 - Razer Seiren V3 Mini: gap of 100.0 ms, clock drift corrected +3.45 ms so far,
    /// +0.012 ms for the gap, lateness 12.30 ms before, 12.41 ms after".
    public static func clockDriftGap(of label: String, _ gap: ClockDriftCorrection.Gap) -> String {
        "\(label): gap of " + String(format: "%.1f ms", Double(gap.length) / 1e6)
            + ", clock drift corrected \(ClockDriftText.signed(gap.applied * 1000, decimals: 2, unit: "ms")) so far, "
            + "\(ClockDriftText.signed(gap.drift * 1000, decimals: 3, unit: "ms")) for the gap, lateness "
            + String(format: "%.2f ms before, %.2f ms after", gap.latenessBefore * 1000, gap.latenessAfter * 1000)
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
