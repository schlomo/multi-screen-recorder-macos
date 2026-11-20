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
            iccProfile: Self.iccProfileText(CVBufferCopyAttachment(pixelBuffer, kCVImageBufferICCProfileKey, nil)),
            contentRect: rect.map { "(\(Self.number($0.origin.x)),\(Self.number($0.origin.y)),\(Self.number($0.width)),\(Self.number($0.height)))" },
            scaleFactor: (info[.scaleFactor] as? NSNumber)?.doubleValue, screenCheck: screenCheck)
    }

    /// "none", or "attached (<bytes> bytes, checksum <FNV-1a>)": a profile whose bytes change is a change.
    private static func iccProfileText(_ profile: CFTypeRef?) -> String {
        guard let profile else { return "none" }
        guard CFGetTypeID(profile) == CFDataGetTypeID() else { return "attached" }
        let data = profile as! CFData as Data
        let checksum = data.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        return "attached (\(data.count) bytes, checksum \(String(checksum, radix: 16)))"
    }

    private static func number(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", Double(value))
    }
}

/// What is compared on every frame, as the buffer's own attachment objects: the
/// strings of `FrameFacts` are built only when this differs from the frame
/// before, which at 30 frames per second a string per attachment would not
/// afford. Everything `FrameFacts` tells is in it, so no change goes unseen.
struct FrameKey: Equatable {
    var width: Int
    var height: Int
    var pixelFormat: UInt32
    var primaries: CFTypeRef?
    var transferFunction: CFTypeRef?
    var yCbCrMatrix: CFTypeRef?
    var iccProfile: CFTypeRef?
    var contentRect: CFTypeRef?
    var scaleFactor: CFTypeRef?
    var screenCheck: String

    init(_ pixelBuffer: CVPixelBuffer, info: [SCStreamFrameInfo: Any], screenCheck: String) {
        width = CVPixelBufferGetWidth(pixelBuffer)
        height = CVPixelBufferGetHeight(pixelBuffer)
        pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        primaries = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, nil)
        transferFunction = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, nil)
        yCbCrMatrix = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, nil)
        iccProfile = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferICCProfileKey, nil)
        contentRect = info[.contentRect] as CFTypeRef?
        scaleFactor = info[.scaleFactor] as CFTypeRef?
        self.screenCheck = screenCheck
    }

    static func == (left: FrameKey, right: FrameKey) -> Bool {
        left.width == right.width && left.height == right.height && left.pixelFormat == right.pixelFormat
            && left.screenCheck == right.screenCheck
            && same(left.primaries, right.primaries) && same(left.transferFunction, right.transferFunction)
            && same(left.yCbCrMatrix, right.yCbCrMatrix) && same(left.iccProfile, right.iccProfile)
            && same(left.contentRect, right.contentRect) && same(left.scaleFactor, right.scaleFactor)
    }

    /// Pointer identity first, then `CFEqual`; two absences are the same.
    private static func same(_ left: CFTypeRef?, _ right: CFTypeRef?) -> Bool {
        switch (left, right) {
        case (nil, nil): true
        case let (left?, right?): left === right || CFEqual(left, right)
        default: false
        }
    }
}
