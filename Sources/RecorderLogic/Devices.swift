/// A display as the system reports it, before it gets its number.
public struct DisplayInfo: Equatable, Sendable {
    public var name: String
    public var pixelSize: FrameSize
    public var isMain: Bool
    /// The top-left corner in the global display space, for numbering left to right.
    public var originX: Double
    public var originY: Double

    public init(name: String, pixelSize: FrameSize, isMain: Bool, originX: Double, originY: Double) {
        self.name = name
        self.pixelSize = pixelSize
        self.isMain = isMain
        self.originX = originX
        self.originY = originY
    }
}

/// A display or audio input the system lists but does not fully describe.
public struct DeviceReadError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public struct NumberedDisplay: Equatable, Sendable {
    public var number: Int
    public var display: DisplayInfo
}

/// Display 1 is the main display; the others are numbered left to right.
public func numberDisplays(_ displays: [DisplayInfo]) -> [NumberedDisplay] {
    displays
        .sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            if lhs.originX != rhs.originX { return lhs.originX < rhs.originX }
            return lhs.originY < rhs.originY
        }
        .enumerated()
        .map { NumberedDisplay(number: $0.offset + 1, display: $0.element) }
}

public struct AudioInputInfo: Equatable, Sendable {
    public var name: String
    public var channelCount: Int
    public var isDefault: Bool

    public init(name: String, channelCount: Int, isDefault: Bool) {
        self.name = name
        self.channelCount = channelCount
        self.isDefault = isDefault
    }

    /// "MacBook Pro Microphone (default)" or just the name.
    public var label: String { isDefault ? "\(name) (default)" : name }
}

/// The text `msr list` prints.
public func renderList(
    displays: [NumberedDisplay],
    resolution: RecordingResolution,
    audioInputs: [AudioInputInfo],
    systemAudioAvailable: Bool
) -> String {
    var lines = ["Displays"]
    if displays.isEmpty {
        lines.append("  none")
    } else {
        let numbers = displays.map { String($0.number) }
        let sizes = displays.map { $0.display.pixelSize.description }
        let numberWidth = numbers.map(\.count).max() ?? 0
        let nameWidth = displays.map(\.display.name.count).max() ?? 0
        let sizeWidth = sizes.map(\.count).max() ?? 0
        for (index, numbered) in displays.enumerated() {
            let frame = resolution.frameSize(forDisplay: numbered.display.pixelSize)
            lines.append(
                "  " + padded(numbers[index], numberWidth)
                    + "  " + padded(numbered.display.name, nameWidth)
                    + "   " + padded(sizes[index], sizeWidth)
                    + "  records at \(frame)")
        }
    }
    lines.append("Audio inputs")
    if audioInputs.isEmpty {
        lines.append("  none")
    } else {
        for input in audioInputs {
            let channels = input.channelCount == 1 ? "1 channel" : "\(input.channelCount) channels"
            lines.append("  \(input.label), \(channels)")
        }
    }
    lines.append(
        systemAudioAvailable
            ? "System audio: available"
            : "System audio: not available without the Screen & System Audio Recording permission")
    return lines.joined(separator: "\n") + "\n"
}

private func padded(_ text: String, _ width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.count))
}
