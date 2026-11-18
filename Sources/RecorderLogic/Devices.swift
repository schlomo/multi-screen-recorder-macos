/// A screen as the system reports it, before it gets its number.
public struct ScreenInfo: Equatable, Sendable {
    public var name: String
    public var pixelSize: FrameSize
    /// What macOS calls "looks like": the size in points.
    public var pointSize: FrameSize
    public var isMain: Bool
    /// The top-left corner in the global screen space, for numbering left to right.
    public var originX: Double
    public var originY: Double

    public init(name: String, pixelSize: FrameSize, pointSize: FrameSize, isMain: Bool, originX: Double, originY: Double) {
        self.name = name
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

    public init(
        name: String, channelCount: Result<Int, DeviceReadError>, isDefault: Bool, transport: AudioTransport = .builtIn,
        uid: String? = nil
    ) {
        self.name = name
        self.channelCount = channelCount
        self.isDefault = isDefault
        self.transport = transport
        self.uid = uid
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
        case .failure(let error): "cannot be read (\(error))"
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
    systemAudioAvailable: Bool
) -> String {
    WhatWillBeRecorded(settings: settings, screens: .success(screens), audioInputs: .success(audioInputs), outputFolder: nil).text
        + (systemAudioAvailable
            ? "System audio: available\n"
            : "System audio: not available, the program running msr (a terminal app) lacks the Screen & System Audio Recording permission\n")
}

func padded(_ text: String, _ width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.count))
}
