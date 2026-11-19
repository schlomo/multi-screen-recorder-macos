/// The review artifact's files: in `review/<scenario>/` of the scratch
/// folder, which survives a passing scenario's folder being deleted.
public enum ReviewNames {
    public static let folder = "review"
    /// The step before the scenarios that shows the app's start window.
    public static let appStep = "app"
    public static let contactSheet = "contact-sheet.png"
    public static let manifest = "recording.json"
    public static let recordingLog = "recording.log"
    /// `msr record`'s standard error, as the driver captured it.
    public static let standardError = "msr.err"

    /// A window's screenshot. Only the light appearance is taken: the app
    /// stays light with `AppleInterfaceStyle` set in its own defaults
    /// domain (tried 2026-11-19).
    public static func screenshot(scenario: String, window: String) -> String {
        "\(scenario)-\(window)-light.png"
    }

    /// The first seconds of a recorded file, cut without re-encoding.
    public static func excerpt(of fileName: String) -> String { "excerpt \(fileName)" }
}
