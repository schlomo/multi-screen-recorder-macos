import CoreGraphics
import CoreMedia
import CoreVideo
import RecorderLogic
@preconcurrency import ScreenCaptureKit

extension FrameFacts {
    /// The facts of a frame: its pixel buffer and its frame info.
    init(_ pixelBuffer: CVPixelBuffer, info: [SCStreamFrameInfo: Any], screenCheck: String = "not judged") {
        let attachment = { (key: CFString) -> String in
            CVBufferCopyAttachment(pixelBuffer, key, nil).map { "\($0)" } ?? "none"
        }
        let rect = (info[.contentRect] as CFTypeRef?).flatMap { value -> CGRect? in
            guard CFGetTypeID(value) == CFDictionaryGetTypeID() else { return nil }
            return CGRect(dictionaryRepresentation: value as! CFDictionary)
        }
        self.init(
            width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer),
            pixelFormat: Self.fourCharacterCode(CVPixelBufferGetPixelFormatType(pixelBuffer)),
            primaries: attachment(kCVImageBufferColorPrimariesKey),
            transferFunction: attachment(kCVImageBufferTransferFunctionKey),
            yCbCrMatrix: attachment(kCVImageBufferYCbCrMatrixKey),
            iccProfile: CVBufferCopyAttachment(pixelBuffer, kCVImageBufferICCProfileKey, nil) == nil ? "none" : "attached",
            contentRect: rect.map { "(\(Self.number($0.origin.x)),\(Self.number($0.origin.y)),\(Self.number($0.width)),\(Self.number($0.height)))" },
            scaleFactor: (info[.scaleFactor] as? NSNumber)?.doubleValue, screenCheck: screenCheck)
    }

    private static func number(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", Double(value))
    }
}
