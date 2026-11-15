/// What a display file says about itself (D46): its reel name, in the
/// timecode track, and metadata items under `keyPrefix`, the app also
/// under the standard QuickTime software key.
public struct DisplayFileMetadata: Equatable, Sendable {
    public static let keyPrefix = "org.schapiro.multiscreenrecorder."
    public static let softwareKey = "com.apple.quicktime.software"

    public var displayUUID: String
    public var displayNumber: Int
    public var displayName: String
    public var frameSize: FrameSize
    /// The recording's start, as the recording manifest's `started`.
    public var recordingStarted: String
    /// The app and its version, as the recording manifest's `app`.
    public var app: String

    public init(displayUUID: String, displayNumber: Int, displayName: String, frameSize: FrameSize, recordingStarted: String, app: String) {
        self.displayUUID = displayUUID
        self.displayNumber = displayNumber
        self.displayName = displayName
        self.frameSize = frameSize
        self.recordingStarted = recordingStarted
        self.app = app
    }

    /// "Display 2 - LG HDR 4K", as in the display file's name.
    public var reelName: String { "Display \(displayNumber) - \(displayName)" }

    /// Each metadata item's full key and value.
    public var items: [(key: String, value: String)] {
        [
            ("displayUUID", displayUUID),
            ("displayNumber", String(displayNumber)),
            ("displayName", displayName),
            ("frameSize", "\(frameSize.width)x\(frameSize.height)"),
            ("recordingStarted", recordingStarted),
            ("app", app),
        ].map { (Self.keyPrefix + $0.0, $0.1) } + [(Self.softwareKey, app)]
    }
}
