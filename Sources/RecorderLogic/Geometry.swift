/// A width and height: in points for what a screen looks like, or in pixels
/// for what it is drawn at.
public struct FrameSize: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var pixelCount: Int { width * height }

    /// 1080p, the frame size the video's bit rate is given for.
    public static let fullHD = FrameSize(width: 1920, height: 1080)

    var isPortrait: Bool { height > width }

    var rotated: FrameSize { FrameSize(width: height, height: width) }

    public var description: String { "\(width)×\(height)" }
}

/// The maximum box a screen's looks-like size is shrunk to fit, or None:
/// no screen is recorded, only audio.
public enum RecordingResolution: String, CaseIterable, Sendable, Encodable {
    /// The size macOS shows as "looks like": no box.
    case native
    case uhd4k = "4k"
    case p1440 = "1440p"
    case p1200 = "1200p"
    case p1080 = "1080p"
    case p720 = "720p"
    /// Audio only: no screen is recorded. Compared with an optional, write
    /// `RecordingResolution.none`: a bare `.none` there means `Optional.none`.
    case none

    /// Every resolution from None and the smallest box to the largest,
    /// native last: the order of the start window's slider.
    public static let smallestFirst: [RecordingResolution] =
        [.none] + allCases.filter { $0.box != nil }.sorted { $0.box!.height < $1.box!.height } + [.native]

    /// Whether a recording at this resolution records the screens: all but None.
    public var recordsScreens: Bool { self != .none }

    /// The position of this resolution on the slider, which runs over `smallestFirst`.
    public var sliderIndex: Double { indexOnSlider(of: self, in: Self.smallestFirst) }

    /// The resolution the slider's `position` selects (rounded, kept in range),
    /// or nil when that is this resolution: nothing to change, save or check.
    public func choosing(sliderPosition position: Double) -> RecordingResolution? {
        sliderChoice(at: position, in: Self.smallestFirst, current: self)
    }

    /// The box, or nil for native, which keeps the looks-like size, and for None.
    public var box: FrameSize? {
        switch self {
        case .native, .none: nil
        case .uhd4k: FrameSize(width: 3840, height: 2160)
        case .p1440: FrameSize(width: 2560, height: 1440)
        case .p1200: FrameSize(width: 1920, height: 1200)
        case .p1080: FrameSize(width: 1920, height: 1080)
        case .p720: FrameSize(width: 1280, height: 720)
        }
    }

    /// The name a person reads, in the app and its texts.
    public var shownName: String {
        switch self {
        case .native: "Native"
        case .none: "None"
        case .uhd4k: "4K"
        case .p1440, .p1200, .p1080, .p720: rawValue
        }
    }

    /// The frame size of a screen file: the screen's looks-like size shrunk
    /// into the box, turned upright for a portrait screen, with its
    /// proportions kept, never enlarged, each side rounded down to an even
    /// number. The size the screen is drawn at is never recorded. None has
    /// no frame size: asking for it is a bug.
    public func frameSize(forLooksLike looksLike: FrameSize) -> FrameSize {
        precondition(recordsScreens, "the recording resolution None records no screen, so it has no frame size")
        let fitted = box.map { fit(looksLike, into: looksLike.isPortrait ? $0.rotated : $0) } ?? looksLike
        return FrameSize(width: roundedDownToEven(fitted.width), height: roundedDownToEven(fitted.height))
    }

    /// Whether a screen's file continues when its looks-like size changes:
    /// only while the frame size stays the same; otherwise the file ends
    /// and a new one starts at the new frame size (D30).
    public func screenFileContinues(from oldLooksLike: FrameSize, to newLooksLike: FrameSize) -> Bool {
        frameSize(forLooksLike: oldLooksLike) == frameSize(forLooksLike: newLooksLike)
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
