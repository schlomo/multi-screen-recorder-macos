/// A width and height in pixels.
public struct FrameSize: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var pixelCount: Int { width * height }

    var isPortrait: Bool { height > width }

    var rotated: FrameSize { FrameSize(width: height, height: width) }

    public var description: String { "\(width)×\(height)" }
}

/// The maximum box a display's picture is shrunk to fit.
public enum RecordingResolution: String, CaseIterable, Sendable {
    case native
    case uhd4k = "4k"
    case p1440 = "1440p"
    case p1200 = "1200p"
    case p1080 = "1080p"
    case p720 = "720p"

    /// The box, or nil for native, which keeps the display's own size.
    public var box: FrameSize? {
        switch self {
        case .native: nil
        case .uhd4k: FrameSize(width: 3840, height: 2160)
        case .p1440: FrameSize(width: 2560, height: 1440)
        case .p1200: FrameSize(width: 1920, height: 1200)
        case .p1080: FrameSize(width: 1920, height: 1080)
        case .p720: FrameSize(width: 1280, height: 720)
        }
    }

    /// The name a person reads, in the app and its texts.
    public var label: String {
        switch self {
        case .native: "Native"
        case .uhd4k: "4K"
        case .p1440, .p1200, .p1080, .p720: rawValue
        }
    }

    /// The frame size of a display file: the display's pixel size shrunk into
    /// the box, turned upright for a portrait display, with its proportions
    /// kept, never enlarged, each side rounded down to an even number.
    public func frameSize(forDisplay display: FrameSize) -> FrameSize {
        let fitted = box.map { fit(display, into: display.isPortrait ? $0.rotated : $0) } ?? display
        return FrameSize(width: roundedDownToEven(fitted.width), height: roundedDownToEven(fitted.height))
    }
}

private func fit(_ size: FrameSize, into box: FrameSize) -> FrameSize {
    guard size.width > box.width || size.height > box.height else { return size }
    // Compare the aspect ratios with integers, so no rounding decides the limiting side.
    if size.width * box.height >= size.height * box.width {
        return FrameSize(width: box.width, height: size.height * box.width / size.width)
    }
    return FrameSize(width: size.width * box.height / size.height, height: box.height)
}

private func roundedDownToEven(_ value: Int) -> Int { value - value % 2 }
