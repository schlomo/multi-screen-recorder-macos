/// Whether a change of an open camera's active format is another app's
/// (D74): CoreMediaIO's "running somewhere" counts the recording's own
/// use, so during a recording only a change the recording did not make
/// tells another app took control. Changes while the recording configures
/// the camera, and one to the format it set, are its own.
public struct ForeignFormatWatch: Equatable, Sendable {
    private var own: CameraFormat?

    public init() {}

    /// The recording's open finished configuring the camera, which now runs in `format`.
    public mutating func opened(in format: CameraFormat) {
        own = format
    }

    /// The camera's active format changed to `format`: whether another app changed it.
    public func isForeign(_ format: CameraFormat) -> Bool {
        own.map { $0 != format } ?? false
    }
}
