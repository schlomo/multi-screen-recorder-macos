/// The recorder's values (*data*, docs/design/recorder.md): starting points,
/// calibrated at the v1 gate. Everything that counts frames derives from
/// `framesPerSecond`.
public enum RecorderValues {
    /// The tick grid's rate and the timecode's: every screen file has this
    /// many frames per second (D11, D21).
    public static let framesPerSecond = 30
    /// How long ticks may wait for a writer that is not ready before its
    /// screen file ends with `screen file writer fell behind`, and how
    /// long the waiting ticks and the last guide track samples are written
    /// at a screen file's end (D53).
    public static let screenFileLateTickSeconds = 6
    /// How long audio waits: guide track samples for a screen file's
    /// writer, a screen file's last mix for its sources' sound up to the
    /// video's end, and an audio file's samples for its writer, also at its end.
    public static let audioWaitBoundSeconds = 2
    /// The fragment length of every file: a crash loses at most this much.
    public static let fragmentSeconds = 2
    /// How long a screen must stay unchanged before its stream starts or
    /// starts again.
    public static let settleTime = Duration.seconds(1)
    /// How long a screen's frames may keep failing the screen check in a
    /// row, outside the settle time, before its screen file ends.
    public static let screenCheckFailureSeconds = 1
    /// The wait before a failed stream is started again, doubling up to the longest.
    public static let firstRestartDelay = Duration.seconds(1)
    public static let longestRestartDelay = Duration.seconds(10)
    /// How often the free space in the recording folder is checked.
    public static let freeSpaceCheckInterval = Duration.seconds(5)
    /// How far a frame's screen rectangle may differ from its screen's
    /// bounds, in points, and still pass the screen check: the two are
    /// whole points, so this only absorbs rounding.
    public static let screenCheckTolerancePoints = 0.5

    public static let lateTickBound = screenFileLateTickSeconds * framesPerSecond
    public static let screenCheckFailuresInARow = screenCheckFailureSeconds * framesPerSecond
}
