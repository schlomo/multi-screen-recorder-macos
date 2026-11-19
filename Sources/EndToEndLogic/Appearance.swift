/// The system appearance a window's screenshot is taken in.
public enum Appearance: String, CaseIterable, Sendable {
    case light
    case dark

    /// The appearances to take: light always, dark only when the driver is
    /// told it runs in the throwaway VM, where changing the system's
    /// appearance harms nobody's session.
    public static func taken(inThrowawayVM: Bool) -> [Appearance] {
        inThrowawayVM ? [.light, .dark] : [.light]
    }
}
