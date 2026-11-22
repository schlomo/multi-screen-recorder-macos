/// What a screen file or a camera file says about itself (D46, D74): its reel name, in the
/// timecode track, and metadata items under `keyPrefix`, the app also
/// under the standard QuickTime software key, the reel name also under the
/// pro apps keys for the reel and the camera name.
public struct ScreenFileMetadata: Equatable, Sendable {
    public static let keyPrefix = "org.schapiro.multiscreenrecorder."
    public static let softwareKey = "com.apple.quicktime.software"
    /// Pro apps keys that may hold the reel name and the camera [CONJECTURE: DaVinci Resolve reads them].
    public static let reelKey = "com.apple.proapps.reel"
    public static let cameraNameKey = "com.apple.proapps.cameraName"

    /// What the file records: a screen by its UUID, or a camera by its unique ID (D74).
    public enum Source: Equatable, Sendable {
        case screen(uuid: String, number: Int, name: String)
        case camera(uniqueID: String, number: Int, name: String)
    }

    public var source: Source
    public var frameSize: FrameSize
    /// The recording's start, as the recording manifest's `started`.
    public var recordingStarted: String
    /// The app and its version, as the recording manifest's `app`.
    public var app: String

    public init(source: Source, frameSize: FrameSize, recordingStarted: String, app: String) {
        self.source = source
        self.frameSize = frameSize
        self.recordingStarted = recordingStarted
        self.app = app
    }

    public init(screenUUID: String, screenNumber: Int, screenName: String, frameSize: FrameSize, recordingStarted: String, app: String) {
        self.init(
            source: .screen(uuid: screenUUID, number: screenNumber, name: screenName), frameSize: frameSize,
            recordingStarted: recordingStarted, app: app)
    }

    /// "Screen 2 - LG HDR 4K" or "Camera 1 - FaceTime HD Camera", as in the
    /// file's name; also the video track's name.
    public var reelName: String {
        switch source {
        case .screen(_, let number, let name): SourceLabel.screen(number, name: name)
        case .camera(_, let number, let name): SourceLabel.camera(number, name: name)
        }
    }

    /// Each metadata item's full key and value.
    public var items: [(key: String, value: String)] {
        let own: [(String, String)] = switch source {
        case .screen(let uuid, let number, let name): [("screenUUID", uuid), ("screenNumber", String(number)), ("screenName", name)]
        case .camera(let uniqueID, let number, let name):
            [("cameraUniqueID", uniqueID), ("cameraNumber", String(number)), ("cameraName", name)]
        }
        return (own + [
            ("frameSize", "\(frameSize.width)x\(frameSize.height)"),
            ("recordingStarted", recordingStarted),
            ("app", app),
        ]).map { (Self.keyPrefix + $0.0, $0.1) } + [(Self.softwareKey, app), (Self.reelKey, reelName), (Self.cameraNameKey, reelName)]
    }
}
