import Foundation

/// This product's repository on GitHub.
public enum GitHubRepository {
    public static let url = URL(string: "https://github.com/schlomo/multi-screen-recorder-macos")!
    public static let issues = url.appending(path: "issues")
}

/// This product's homepage, built from `homepage/`.
public enum Homepage {
    public static let url = URL(string: "https://multiscreenrecorder.schapiro.org")!
}

/// The product's claim (D55): the app's header and the homepage's tagline,
/// always shown as its two lines.
public enum Claim {
    public static let lines = ["Every screen, all audio.", "Keeps going when things change."]
    /// The two lines as one, where a single line is needed.
    public static let text = lines.joined(separator: " ")
}
