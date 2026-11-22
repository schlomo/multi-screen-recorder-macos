/// Why a screen's or a camera's stream ended by itself; the recorder reports it.
public enum VideoStreamEnd: Equatable, Sendable {
    case streamFailed(ErrorDetail)
    /// The screen or camera the stream captured is gone, as on an unplug, often
    /// seconds before macOS's notice of the change: no failure (F4).
    case captureSourceGone
    case writerFailed(ErrorDetail)
    case writerFellBehind
    case diskFull
    /// A screen's only: the screen check failed.
    case showsAnotherScreen
}
