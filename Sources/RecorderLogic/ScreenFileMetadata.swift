/// What a screen file says about itself (D46): its reel name, in the
/// timecode track, and metadata items under `keyPrefix`, the app also
/// under the standard QuickTime software key, the reel name also under the
/// pro apps keys for the reel and the camera name.
public struct ScreenFileMetadata: Equatable, Sendable {
    public static let keyPrefix = "org.schapiro.multiscreenrecorder."
    public static let softwareKey = "com.apple.quicktime.software"
    /// Pro apps keys that may hold the reel name and the camera [CONJECTURE: DaVinci Resolve reads them].
    public static let reelKey = "com.apple.proapps.reel"
    public static let cameraNameKey = "com.apple.proapps.cameraName"

    public var screenUUID: String
    public var screenNumber: Int
    public var screenName: String
    public var frameSize: FrameSize
    /// The recording's start, as the recording manifest's `started`.
    public var recordingStarted: String
    /// The app and its version, as the recording manifest's `app`.
    public var app: String

    public init(screenUUID: String, screenNumber: Int, screenName: String, frameSize: FrameSize, recordingStarted: String, app: String) {
        self.screenUUID = screenUUID
        self.screenNumber = screenNumber
        self.screenName = screenName
        self.frameSize = frameSize
        self.recordingStarted = recordingStarted
        self.app = app
    }

    /// "Screen 2 - LG HDR 4K", as in the screen file's name; also the
    /// video track's name.
    public var reelName: String { "Screen \(screenNumber) - \(screenName)" }

    /// Each metadata item's full key and value.
    public var items: [(key: String, value: String)] {
        [
            ("screenUUID", screenUUID),
            ("screenNumber", String(screenNumber)),
            ("screenName", screenName),
            ("frameSize", "\(frameSize.width)x\(frameSize.height)"),
            ("recordingStarted", recordingStarted),
            ("app", app),
        ].map { (Self.keyPrefix + $0.0, $0.1) } + [(Self.softwareKey, app), (Self.reelKey, reelName), (Self.cameraNameKey, reelName)]
    }
}
