/// The recorder's values (*data*, docs/design/recorder.md): starting points,
/// calibrated at the v1 gate. Everything that counts frames derives from
/// `framesPerSecond`.
public enum RecorderValues {
    /// The tick grid's rate and the timecode's: every screen file has this
    /// many frames per second (D11, D21).
    public static let framesPerSecond = 30
    /// How long ticks may wait for a writer that is not ready before its
    /// video file ends with `screen file writer fell behind` or `camera file
    /// writer fell behind`, and how long the waiting ticks and the last guide
    /// track samples are written at a video file's end (D53).
    public static let videoFileLateTickSeconds = 6
    /// How long audio waits: guide track samples for a screen file's
    /// writer, a screen file's last mix for its sources' sound up to the
    /// video's end, and an audio file's samples for its writer, also at its end.
    public static let audioWaitBoundSeconds = 2
    /// The fragment length of every file: a crash loses at most this much of an audio file, and up to
    /// `guideTrackDelay` more of a video file, its fragment waiting for its guide samples (D80).
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
    /// How long a camera's capture may wait for its first frame, an iPhone's
    /// (Continuity Camera) longer, and then between frames, before its
    /// stream counts as failing; no frame for `cameraStallLimit` is a stall,
    /// the file going on (D74).
    public static let cameraFirstFrameLimit = Duration.seconds(5)
    public static let continuityCameraFirstFrameLimit = Duration.seconds(10)
    public static let cameraFrameGapLimit = Duration.seconds(10)
    public static let cameraStallLimit = Duration.seconds(2)
    /// The seconds within which the audio delays of the audio inputs the "Audio inputs" guide track mixes lie
    /// of each other, early or late; an input outside the largest such group leaves it (D79, D80).
    public static let guideTrackSyncLimit = 0.8
    /// The largest a camera file is: a camera's box is the recording
    /// resolution's limited to this, turned upright for a portrait format (D74).
    public static let cameraLargestSize = FrameSize(width: 1920, height: 1080)
    /// How long a camera file's tick waits for a frame captured after it (D74).
    public static let cameraDecisionDelay = Duration.milliseconds(500)
    /// How often the free space in the recording folder is checked.
    public static let freeSpaceCheckInterval = Duration.seconds(5)
    /// The longest detail lines wait in memory before the recording log gets them (D64).
    public static let recordingLogFlushInterval = Duration.seconds(10)
    /// How far a frame's screen rectangle may differ from its screen's
    /// bounds, in points, and still pass the screen check: the two are
    /// whole points, so this only absorbs rounding.
    public static let screenCheckTolerancePoints = 0.5

    public static let lateTickBound = videoFileLateTickSeconds * framesPerSecond
    public static let screenCheckFailuresInARow = screenCheckFailureSeconds * framesPerSecond
}
