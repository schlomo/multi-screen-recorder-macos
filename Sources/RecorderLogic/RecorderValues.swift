/// The recorder's values (*data*, docs/design/recorder.md): starting points,
/// calibrated at the v1 gate. Everything that counts frames derives from
/// `framesPerSecond`.
public enum RecorderValues {
    /// The tick grid's rate and the timecode's: every display file has this
    /// many frames per second (D11, D21).
    public static let framesPerSecond = 30
    /// How long ticks may wait for a writer that is not ready before its
    /// display file ends with `display file writer fell behind`.
    public static let lateTickBoundSeconds = 2
    /// The fragment length of every file: a crash loses at most this much.
    public static let fragmentSeconds = 2
    /// How long a display must stay unchanged before its stream starts or
    /// starts again.
    public static let settleTime = Duration.seconds(1)
    /// How long a display's frames may keep failing the display check in a
    /// row, outside the settle time, before its display file ends.
    public static let displayCheckFailureSeconds = 1
    /// The wait before a failed stream is started again, doubling up to the longest.
    public static let firstRestartDelay = Duration.seconds(1)
    public static let longestRestartDelay = Duration.seconds(10)
    /// How often the free space in the recording folder is checked.
    public static let freeSpaceCheckInterval = Duration.seconds(5)
    /// How far a frame's screen rectangle may differ from its display's
    /// bounds, in points, and still pass the display check: the two are
    /// whole points, so this only absorbs rounding.
    public static let displayCheckTolerancePoints = 0.5

    public static let lateTickBound = lateTickBoundSeconds * framesPerSecond
    public static let displayCheckFailuresInARow = displayCheckFailureSeconds * framesPerSecond
}
