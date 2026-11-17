/// How an audio input is connected to the Mac, as Core Audio reports its
/// transport type.
public enum AudioTransport: Equatable, Sendable, CaseIterable {
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

    /// Why an input of this transport may be left out, as the table of what will be recorded says it
    /// after its name; nil for a transport that is no reason.
    public var reasonNotRecorded: String? {
        switch self {
        case .bluetooth, .bluetoothLE: "Bluetooth"
        case .virtual: "virtual"
        case .aggregate: "aggregate"
        case .airPlay: "AirPlay"
        case .continuityCapture: "Continuity Capture"
        case .builtIn, .usb, .fireWire, .pci, .thunderbolt, .hdmi, .displayPort, .unknown, .unreadable: nil
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
