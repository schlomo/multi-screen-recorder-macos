/// The lines at the top of the app's window saying what Start records, from
/// the settings and the devices connected now.
public enum RecordingSummary {
    public static func lines(
        settings: Settings,
        displays: Result<[DisplayInfo], DeviceReadError>,
        defaultMicrophone: String?
    ) -> [String] {
        [
            "Records every display, each into its own file at \(sizeText(settings.resolution)): \(displaysText(displays)).",
            "Audio: \(audioText(settings: settings, defaultMicrophone: defaultMicrophone)).",
            "Files go to \(settings.outputFolder). Recording continues when displays or audio sources change.",
        ]
    }

    private static func sizeText(_ resolution: RecordingResolution) -> String {
        resolution == .native ? "its native size" : "up to \(resolution.label)"
    }

    private static func displaysText(_ displays: Result<[DisplayInfo], DeviceReadError>) -> String {
        switch displays {
        case .success(let displays) where displays.isEmpty: "none is connected now"
        case .success(let displays): "now " + listed(numberDisplays(displays).map(\.display.name))
        case .failure: "the displays cannot be read now"
        }
    }

    private static func audioText(settings: Settings, defaultMicrophone: String?) -> String {
        var sources: [String] = []
        if settings.audioMode == .defaultMicrophone {
            sources.append(defaultMicrophone.map { "\($0) (default)" } ?? "no microphone")
        }
        if settings.systemAudio { sources.append("system audio") }
        return sources.isEmpty ? "none" : listed(sources)
    }

    private static func listed(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}

/// Text about the product, written once.
public enum ProductText {
    /// The opening paragraph of README.md, also shown in the About window.
    public static let purpose = "A reliable multi-source screen and audio recorder for macOS. It captures every"
        + " display and audio source, never loses a recording, and keeps going when screens, resolutions or audio"
        + " sources change."
}
