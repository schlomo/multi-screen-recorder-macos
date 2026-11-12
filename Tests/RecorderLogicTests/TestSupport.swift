import Foundation
@testable import RecorderLogic

/// The displays and audio inputs of the examples in docs/design/recorder.md.
enum DesignExample {
    static let displays = [
        DisplayInfo(name: "LG HDR 4K", pixelSize: FrameSize(width: 3840, height: 2160), isMain: false, originX: 1728, originY: 0),
        DisplayInfo(name: "Built-in Retina Display", pixelSize: FrameSize(width: 3456, height: 2234), isMain: true, originX: 0, originY: 0),
    ]
    static let audioInputs = [
        AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: true),
        AudioInputInfo(name: "RØDE Wireless GO II RX", channelCount: 2, isDefault: false),
    ]
}

/// A file of this repository, so a test can hold a document to the code.
func repositoryFile(_ path: String) throws -> String {
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}
