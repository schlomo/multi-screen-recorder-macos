import CoreVideo
import RecorderLogic

/// A camera frame's luma on a grid of about
/// `CameraOrientation.samplesAlongTheLongSide` samples along its long side,
/// each the pixel at the middle of its cell, for telling its picture's
/// orientation (D76); nil for a frame not in a bi-planar Y'CbCr format, whose
/// luma is not one plane.
func sampledLuma(of pixelBuffer: CVPixelBuffer) -> CameraOrientation.Luma? {
    let blackLevel: UInt8
    switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: blackLevel = 16
    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: blackLevel = 0
    default: return nil
    }
    let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
    let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
    let step = max(1, max(width, height) / CameraOrientation.samplesAlongTheLongSide)
    let columns = width / step, rows = height / step
    guard columns > 0, rows > 0, CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
    let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
    let plane = base.assumingMemoryBound(to: UInt8.self)
    var samples = [UInt8](repeating: 0, count: columns * rows)
    for row in 0..<rows {
        let line = plane + (row * step + step / 2) * bytesPerRow
        for column in 0..<columns { samples[row * columns + column] = line[column * step + step / 2] }
    }
    return CameraOrientation.Luma(width: columns, height: rows, samples: samples, blackLevel: blackLevel)
}
