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

/// The product's claim (D55): the app's header and the homepage's tagline.
public enum Claim {
    public static let text = "Every screen, all audio. Keeps going when things change."
}
