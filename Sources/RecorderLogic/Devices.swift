/// A screen as the system reports it, before it gets its number.
public struct ScreenInfo: Equatable, Sendable {
    public var name: String
    /// Core Graphics' display ID, 0 where not read.
    public var displayID: UInt32
    /// The screen mode's refresh rate in Hz, nil where macOS reports none.
    public var refreshRate: Double?
    public var pixelSize: FrameSize
    /// What macOS calls "looks like": the size in points.
    public var pointSize: FrameSize
    public var isMain: Bool
    /// The top-left corner in the global screen space, for numbering left to right.
    public var originX: Double
    public var originY: Double

    public init(
        name: String, pixelSize: FrameSize, pointSize: FrameSize, isMain: Bool, originX: Double, originY: Double,
        displayID: UInt32 = 0, refreshRate: Double? = nil
    ) {
        self.name = name
        self.displayID = displayID
        self.refreshRate = refreshRate
        self.pixelSize = pixelSize
        self.pointSize = pointSize
        self.isMain = isMain
        self.originX = originX
        self.originY = originY
    }

    /// "3440×1440", or "looks like 3440×1440, drawn at 6880×2880" when the
    /// screen draws more pixels than its points.
    public var sizeText: String {
        pointSize == pixelSize ? pixelSize.description : "looks like \(pointSize), drawn at \(pixelSize)"
    }
}

/// A screen or audio input the system lists but does not fully describe.
public struct DeviceReadError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public struct NumberedScreen: Equatable, Sendable {
    public var number: Int
    public var screen: ScreenInfo
}

/// Screen 1 is the main screen; the others are numbered left to right.
public func numberScreens(_ screens: [ScreenInfo]) -> [NumberedScreen] {
    screens
        .sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            if lhs.originX != rhs.originX { return lhs.originX < rhs.originX }
            return lhs.originY < rhs.originY
        }
        .enumerated()
        .map { NumberedScreen(number: $0.offset + 1, screen: $0.element) }
}

public struct AudioInputInfo: Equatable, Sendable {
    public var name: String
    /// The number of channels, or why it cannot be read; each input is read by itself.
    public var channelCount: Result<Int, DeviceReadError>
    public var isDefault: Bool
    public var transport: AudioTransport
    /// The Core Audio UID, by which a recording knows the input and opens it;
    /// nil when it cannot be read.
    public var uid: String?
    /// Core Audio's nominal sample rate, nil where it cannot be read.
    public var sampleRate: Double?
    /// Its own input volume, nil for an input that has none.
    public var inputVolume: InputVolumeReading?

    public init(
        name: String, channelCount: Result<Int, DeviceReadError>, isDefault: Bool, transport: AudioTransport = .builtIn,
        uid: String? = nil, sampleRate: Double? = nil, inputVolume: InputVolumeReading? = nil
    ) {
        self.name = name
        self.channelCount = channelCount
        self.isDefault = isDefault
        self.transport = transport
        self.uid = uid
        self.sampleRate = sampleRate
        self.inputVolume = inputVolume
    }

    public init(name: String, channelCount: Int, isDefault: Bool, transport: AudioTransport = .builtIn, uid: String? = nil) {
        self.init(name: name, channelCount: .success(channelCount), isDefault: isDefault, transport: transport, uid: uid)
    }

    /// "MacBook Pro Microphone (default)" or just the name.
    public var shownName: String { isDefault ? "\(name) (default)" : name }

    public var channelsText: String {
        switch channelCount {
        case .success(1): "1 channel"
        case .success(let count): "\(count) channels"
        case .failure(let error): "cannot be read (\(ErrorDetail(error).text))"
        }
    }
}

/// The audio inputs a recording with these settings records whose channels cannot be read.
public func unreadableRecordedInputs(_ audioInputs: [AudioInputInfo], settings: Settings) -> [AudioInputInfo] {
    audioInputs.filter { input in
        guard AudioTracker.records(input, settings: settings), case .failure = input.channelCount else { return false }
        return true
    }
}

/// The audio inputs a recording with these settings is judged by: with the
/// audio mode none, an empty list, whether or not the audio inputs can be
/// read, as none of them is recorded; otherwise `audioInputs` as they are.
public func audioInputsToJudge(
    _ audioInputs: Result<[AudioInputInfo], DeviceReadError>, settings: Settings
) -> Result<[AudioInputInfo], DeviceReadError> {
    switch settings.effectiveAudioMode {
    case .none: .success([])
    case .defaultMicrophone, .wired, .allInputs: audioInputs
    }
}

/// The screens a recording with these settings is judged by: at the
/// recording resolution None an empty list, whether or not the screens can be read,
/// as none of them is recorded; otherwise `screens` as they are.
public func screensToJudge<Failure: Error>(
    _ screens: Result<[ScreenInfo], Failure>, settings: Settings
) -> Result<[ScreenInfo], Failure> {
    settings.effectiveResolution.recordsScreens ? screens : .success([])
}

/// The text `msr list` prints: the table of what will be recorded, as `msr check` prints it, and
/// whether the system audio can be recorded by the program running `msr`.
public func renderList(
    settings: Settings,
    screens: [ScreenInfo],
    audioInputs: [AudioInputInfo],
    cameras: [CameraInfo],
    cameraPermissionDenied: Bool = false,
    systemAudioAvailable: Bool
) -> String {
    WhatWillBeRecorded(
        settings: settings, screens: .success(screens), audioInputs: .success(audioInputs), cameras: cameras,
        cameraPermissionDenied: cameraPermissionDenied, outputFolder: nil
    ).text
        + (systemAudioAvailable
            ? "System audio: available\n"
            : "System audio: not available, the program running msr (a terminal app) lacks the Screen & System Audio Recording permission\n")
}

func padded(_ text: String, _ width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.count))
}

/// One way a camera can deliver its picture: its size in pixels and the
/// frame rates it delivers at that size.
public struct CameraFormat: Equatable, Sendable, CustomStringConvertible {
    public var size: FrameSize
    public var maxFramesPerSecond: Double
    public var minFramesPerSecond: Double

    /// `minFramesPerSecond` defaults to `maxFramesPerSecond`: a single rate.
    public init(size: FrameSize, maxFramesPerSecond: Double, minFramesPerSecond: Double? = nil) {
        self.size = size
        self.maxFramesPerSecond = maxFramesPerSecond
        self.minFramesPerSecond = minFramesPerSecond ?? maxFramesPerSecond
    }

    /// "1920×1080 at 30 fps".
    public var description: String { "\(size) at \(String(format: "%g", maxFramesPerSecond)) fps" }

    /// "1920×1080 5–60 fps", or "1920×1080 30 fps" for a single rate.
    public var rangeText: String { "\(size) \(Self.ratesText(minFramesPerSecond...maxFramesPerSecond))" }

    /// "5–60 fps", or "30 fps" for a single rate.
    public static func ratesText(_ rates: ClosedRange<Double>) -> String {
        let bound = { (rate: Double) in String(format: "%g", (rate * 100).rounded() / 100) }
        return rates.lowerBound == rates.upperBound ? "\(bound(rates.upperBound)) fps" : "\(bound(rates.lowerBound))–\(bound(rates.upperBound)) fps"
    }

    /// One format per frame size, as `preferred` orders them, its rates
    /// from the lowest to the highest of any variant at that size: what a
    /// camera offers, for reading.
    public static func offered(_ listed: [CameraFormat]) -> [CameraFormat] {
        Dictionary(grouping: listed, by: \.size).map { size, variants in
            CameraFormat(size: size, maxFramesPerSecond: variants.map(\.maxFramesPerSecond).max()!,
                         minFramesPerSecond: variants.map(\.minFramesPerSecond).min()!)
        }.sorted { ($0.size.pixelCount, $0.size.width, $0.size.height) < ($1.size.pixelCount, $1.size.width, $1.size.height) }
    }

    /// Whether it delivers the tick grid's frame rate, a rate rounded to whole frames per second.
    var deliversTheTickRate: Bool { maxFramesPerSecond.rounded() >= Double(TickGrid.recording.framesPerSecond) }

    /// One format per frame size, smallest first (of equal pixel counts the
    /// narrower, then the lower), of a camera's formats as listed: the
    /// variant with the lowest rate that still delivers the tick grid's
    /// frame rate, or the fastest where none does (D74).
    public static func preferred(_ listed: [CameraFormat]) -> [CameraFormat] {
        Dictionary(grouping: listed, by: \.size).values.compactMap { variants in
            variants.filter(\.deliversTheTickRate).min { $0.maxFramesPerSecond < $1.maxFramesPerSecond }
                ?? variants.max { $0.maxFramesPerSecond < $1.maxFramesPerSecond }
        }.sorted { ($0.size.pixelCount, $0.size.width, $0.size.height) < ($1.size.pixelCount, $1.size.width, $1.size.height) }
    }

    /// How to set the frame duration for `wanted` frames per second
    /// (`frameRate(closestTo:in:)`): a rate at a range's bound takes the
    /// bound's own duration as the device lists it, so the device takes it;
    /// a rate inside a range is 1/`wanted`.
    public enum FrameDuration: Equatable, Sendable {
        /// The range's shortest frame duration, its highest rate.
        case shortestOf(range: Int)
        /// The range's longest frame duration, its lowest rate.
        case longestOf(range: Int)
        case oneOver(Int)
    }

    /// The frame duration to set for `wanted` frames per second, nil without a range.
    public static func frameDuration(closestTo wanted: Int, in ranges: [ClosedRange<Double>]) -> FrameDuration? {
        guard let rate = frameRate(closestTo: Double(wanted), in: ranges),
              let range = ranges.firstIndex(where: { $0.contains(rate) })
        else { return nil }
        if rate == ranges[range].upperBound { return .shortestOf(range: range) }
        if rate == ranges[range].lowerBound { return .longestOf(range: range) }
        return .oneOver(wanted)
    }

    /// The frame rate to set: `wanted` where one of the format's ranges
    /// allows it, otherwise the allowed rate closest to it; nil without a range.
    public static func frameRate(closestTo wanted: Double, in ranges: [ClosedRange<Double>]) -> Double? {
        ranges.map { min(max(wanted, $0.lowerBound), $0.upperBound) }.min { abs($0 - wanted) < abs($1 - wanted) }
    }
}

/// A camera as AVFoundation lists it, known by its unique ID (D74).
public struct CameraInfo: Equatable, Sendable {
    /// AVFoundation's unique ID, by which a recording knows the camera and opens it.
    public var uniqueID: String
    public var name: String
    /// The Mac's default camera.
    public var isDefault: Bool
    /// A camera made by software, such as OBS Virtual Camera, not a device.
    public var isVirtual: Bool
    /// An iPhone's camera: a Continuity Camera or Desk View, or connected by Continuity Capture.
    public var isContinuity: Bool
    public var formats: [CameraFormat]
    /// Suspended by macOS, as a laptop's camera with its lid closed: it delivers no picture.
    public var isSuspended: Bool
    /// The format the camera runs in now, nil where it cannot be read.
    public var activeFormat: CameraFormat?
    /// The camera runs, as CoreMediaIO says (`kCMIODevicePropertyDeviceIsRunningSomewhere`):
    /// read before the recording opens it, another app uses it, and the recording keeps
    /// its active format. AVFoundation's `isInUseByAnotherApplication` misses a browser's use (D74).
    public var isRunningElsewhere: Bool
    /// How AVFoundation says the camera is connected (`transportType`, as Core Audio's).
    public var transport: AudioTransport
    /// Each frame size the camera offers once, with all its rates (`CameraFormat.offered`).
    public var offeredFormats: [CameraFormat]
    /// The frame rates the camera runs at now, nil where they cannot be read.
    public var activeFrameRates: ClosedRange<Double>?
    /// The speed of a USB camera's link, nil for another camera or where it cannot be read.
    public var usbSpeed: USBSpeed?

    public init(
        uniqueID: String, name: String, isDefault: Bool, isVirtual: Bool, isContinuity: Bool = false, formats: [CameraFormat],
        isSuspended: Bool = false, activeFormat: CameraFormat? = nil, isRunningElsewhere: Bool = false,
        transport: AudioTransport = .unknown, offeredFormats: [CameraFormat] = [], activeFrameRates: ClosedRange<Double>? = nil,
        usbSpeed: USBSpeed? = nil
    ) {
        self.uniqueID = uniqueID
        self.name = name
        self.isDefault = isDefault
        self.isVirtual = isVirtual
        self.isContinuity = isContinuity
        self.formats = formats
        self.isSuspended = isSuspended
        self.activeFormat = activeFormat
        self.isRunningElsewhere = isRunningElsewhere
        self.transport = transport
        self.offeredFormats = offeredFormats
        self.activeFrameRates = activeFrameRates
        self.usbSpeed = usbSpeed
    }

    /// The format a recording at `resolution` records the camera in (D74).
    /// One another app uses keeps its active format, never changed. Else,
    /// as for screens: each format that delivers the tick grid's frame rate,
    /// of any aspect ratio, records its size fitted into the camera's box
    /// (`cameraFrameSize(for:)`, never enlarged, a portrait one against the
    /// box turned upright); the format with the largest recorded size, and of
    /// those the smallest, the least to decode, then the one turned as the
    /// camera's active format (portrait, landscape or square), then
    /// landscape before the rest, then the narrower. A
    /// camera with no format at that rate delivers its fastest, the largest
    /// of those. Nil for a camera that lists no format.
    public func chosenFormat(resolution: RecordingResolution, limited: Bool = true) -> CameraFormat? {
        if isRunningElsewhere, let activeFormat { return activeFormat }
        let fastEnough = formats.filter(\.deliversTheTickRate)
        guard !fastEnough.isEmpty else {
            return formats.max { ($0.maxFramesPerSecond.rounded(), $0.size.pixelCount) < ($1.maxFramesPerSecond.rounded(), $1.size.pixelCount) }
        }
        let recorded = { (format: CameraFormat) in resolution.cameraFrameSize(for: format.size, limited: limited).pixelCount }
        // The active format's orientation is the picture the camera means: the Osmo's 9:16 mode is
        // 1080×1920, also listed pillarboxed as 1920×1080, while the FaceTime camera means 1920×1080.
        let inActiveOrientation = { (format: CameraFormat) in activeFormat.map { Self.orientation(of: $0.size) == Self.orientation(of: format.size) } ?? false }
        let key = { (format: CameraFormat) in
            (recorded(format), -format.size.pixelCount, inActiveOrientation(format) ? 1 : 0,
             format.size.width > format.size.height ? 1 : 0, -format.size.width)
        }
        return fastEnough.max { key($0) < key($1) }
    }

    /// The frame size of the camera's file: its chosen format's size, fitted
    /// into the camera's box; nil at None, which records no camera.
    public func frameSize(resolution: RecordingResolution, limited: Bool = true) -> FrameSize? {
        guard resolution.recordsScreens else { return nil }
        return chosenFormat(resolution: resolution, limited: limited).map { resolution.cameraFrameSize(for: $0.size, limited: limited) }
    }

    /// The format of `format`'s size turned, portrait for landscape or the
    /// other way, that delivers the tick grid's frame rate; nil where the
    /// camera offers none, or `format` is square (D76).
    public func otherOrientation(of format: CameraFormat) -> CameraFormat? {
        let turned = FrameSize(width: format.size.height, height: format.size.width)
        guard turned != format.size else { return nil }
        return formats.first { $0.size == turned && $0.deliversTheTickRate }
    }

    /// Portrait (-1), square (0) or landscape (1).
    static func orientation(of size: FrameSize) -> Int { (size.width - size.height).signum() }

    /// "FaceTime HD Camera (default)" or just the name.
    public var shownName: String { isDefault ? "\(name) (default)" : name }
}

/// An audio input's own input volume: its value, 0 to 1 (nil where it
/// cannot be read), and whether Core Audio lets it be set (D69).
public struct InputVolumeReading: Equatable, Sendable {
    public var value: Double?
    public var isSettable: Bool

    public init(value: Double?, isSettable: Bool) {
        self.value = value
        self.isSettable = isSettable
    }
}

/// A USB device's link speed, as IOKit's `USBSpeed` registry property
/// numbers it (`tIOUSBHostConnectionSpeed`).
public enum USBSpeed: Int, Equatable, Sendable {
    case full = 1, low, high, superSpeed, superSpeedPlus, superSpeedPlusBy2

    /// "480 Mb/s (USB 2)".
    public var text: String {
        switch self {
        case .low: "1.5 Mb/s (USB 1)"
        case .full: "12 Mb/s (USB 1)"
        case .high: "480 Mb/s (USB 2)"
        case .superSpeed: "5 Gb/s (USB 3)"
        case .superSpeedPlus: "10 Gb/s (USB 3)"
        case .superSpeedPlusBy2: "20 Gb/s (USB 3)"
        }
    }

    /// USB 2 or slower.
    public var isAtMostUSB2: Bool { self == .low || self == .full || self == .high }

    /// The USB location ID a USB camera's unique ID starts with: "0x20522000" in "0x20522000046d085e".
    public static func locationID(ofUniqueID uniqueID: String) -> UInt32? {
        guard uniqueID.hasPrefix("0x"), uniqueID.count >= 10 else { return nil }
        return UInt32(uniqueID.dropFirst(2).prefix(8), radix: 16)
    }
}
