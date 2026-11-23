/// How an audio input or a camera is connected to the Mac, as Core Audio
/// (for a camera, AVFoundation) reports its transport type.
public enum DeviceTransport: Equatable, Sendable, CaseIterable {
    case builtIn
    case usb
    case fireWire
    case pci
    case thunderbolt
    case hdmi
    case displayPort
    case bluetooth
    case bluetoothLE
    case virtual
    case aggregate
    case airPlay
    case continuityCapture
    /// A transport type this app does not know.
    case unknown
    /// A transport type that could not be read.
    case unreadable

    /// Why an input of this transport is not wired, as the table of what will be recorded says it after its
    /// name; nil for a wired transport.
    public var notWiredReason: String? {
        switch self {
        case .bluetooth, .bluetoothLE: "Bluetooth"
        case .virtual: "virtual"
        case .aggregate: "aggregate"
        case .airPlay: "AirPlay"
        case .continuityCapture: "Continuity Capture"
        case .unknown, .unreadable: "unknown connection"
        case .builtIn, .usb, .fireWire, .pci, .thunderbolt, .hdmi, .displayPort: nil
        }
    }

    /// "USB", "built in", "Bluetooth" and so on.
    public var shownName: String {
        switch self {
        case .builtIn: "built in"
        case .usb: "USB"
        case .fireWire: "FireWire"
        case .pci: "PCI"
        case .thunderbolt: "Thunderbolt"
        case .hdmi: "HDMI"
        case .displayPort: "DisplayPort"
        case .bluetooth: "Bluetooth"
        case .bluetoothLE: "Bluetooth LE"
        case .virtual: "virtual"
        case .aggregate: "aggregate"
        case .airPlay: "AirPlay"
        case .continuityCapture: "Continuity Capture"
        case .unknown: "unknown"
        case .unreadable: "cannot be read"
        }
    }

    /// Whether the audio mode Wired records an input of this transport: the
    /// built-in and the wired ones. Every other transport, an unknown one and
    /// one that cannot be read included, is not wired.
    public var isWired: Bool {
        switch self {
        case .builtIn, .usb, .fireWire, .pci, .thunderbolt, .hdmi, .displayPort: true
        case .bluetooth, .bluetoothLE, .virtual, .aggregate, .airPlay, .continuityCapture, .unknown, .unreadable: false
        }
    }
}
