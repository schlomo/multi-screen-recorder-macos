/// Text about the product, written once.
public enum ProductText {
    /// The opening paragraph of README.md, also shown in the About window.
    public static let purpose = "A reliable multi-source screen and audio recorder for macOS. It captures every"
        + " display and audio source, never loses a recording, and keeps going when screens, resolutions or audio"
        + " sources change."

    /// Said under the table of what will be recorded, in the window and by
    /// `msr record`, until the audio half of the recording core (B2, D45).
    public static let displaysOnly = "This build records the displays only; audio comes with the next version."
}
