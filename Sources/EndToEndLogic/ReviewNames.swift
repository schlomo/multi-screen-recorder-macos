/// The review artifact's files: in `review/<scenario>/` of the scratch
/// folder, the quick look beside the scenarios' whole folders.
public enum ReviewNames {
    public static let folder = "review"
    /// The step before the scenarios that shows the app's start window.
    public static let appStep = "app"
    public static let contactSheet = "contact-sheet.png"
    public static let manifest = "recording.json"
    public static let recordingLog = "recording.log"
    /// The recording folder's timeline file (D68) is no recorded file.
    public static let timelineFileExtension = "otio"
    /// `msr record`'s standard error, as the driver captured it.
    public static let standardError = "msr.err"

    /// A window's screenshot in an appearance.
    public static func screenshot(scenario: String, window: String, appearance: Appearance) -> String {
        "\(scenario)-\(window)-\(appearance.rawValue).png"
    }

    /// A window's video, of its last seconds before the recording's Stop.
    public static func video(scenario: String, window: String, appearance: Appearance) -> String {
        "\(scenario)-\(window)-\(appearance.rawValue).mov"
    }

    /// The first seconds of a recorded file, cut without re-encoding.
    public static func excerpt(of fileName: String) -> String { "excerpt \(fileName)" }
}
