import CoreGraphics
import CoreText
import EndToEndLogic
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The review artifact of one scenario, in `review/<scenario>/` of the
/// scratch folder: its `recording.json` and `recording.log`, a contact sheet with a still from
/// the middle of each screen file, and the first seconds of one screen
/// file and of the loopback device's audio file. What it shows is for a
/// person to look at, not asserted.
struct Review {
    let folder: URL
    let media: Media

    init(scratch: URL, scenario: String, media: Media) throws {
        folder = scratch.appending(path: ReviewNames.folder).appending(path: scenario)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.media = media
    }

    static func clear(scratch: URL) {
        try? FileManager.default.removeItem(at: scratch.appending(path: ReviewNames.folder))
    }

    func collect(recording: URL, files: [ListedFile], probed: [String: ProbedFile], playsTone: Bool) throws {
        try FileManager.default.copyItem(at: recording.appending(path: ReviewNames.manifest),
                                         to: folder.appending(path: ReviewNames.manifest))
        try FileManager.default.copyItem(at: recording.appending(path: ReviewNames.recordingLog),
                                         to: folder.appending(path: ReviewNames.recordingLog))
        let screenFiles = files.filter { !$0.source.isAudio }
        try contactSheet(screenFiles.map { file in
            let length = probed[file.name]?.video.first?.duration ?? 0
            return (file.name, recording.appending(path: file.name), length / 2)
        })
        // The smallest screen file, so the artifact stays small.
        let smallest = screenFiles.min { size(recording.appending(path: $0.name)) < size(recording.appending(path: $1.name)) }
        var excerpted = smallest.map { [$0.name] } ?? []
        if playsTone {
            excerpted += files.filter { if case .audioInput(let uid, _, _) = $0.source { uid == Machine.loopbackUID } else { false } }
                .prefix(1).map(\.name)
        }
        for name in excerpted {
            try media.excerpt(recording.appending(path: name), seconds: EndToEndValues.reviewExcerptSeconds,
                              to: folder.appending(path: ReviewNames.excerpt(of: name)))
        }
    }

    private func size(_ file: URL) -> Int {
        (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
    }

    /// One PNG: each screen file's still under a strip with its name.
    private func contactSheet(_ stills: [(name: String, file: URL, at: Double)]) throws {
        guard !stills.isEmpty else { return }
        let layout = ContactSheetLayout(count: stills.count)
        guard let context = CGContext(
            data: nil, width: layout.width, height: layout.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw DriverError("cannot make the contact sheet's bitmap") }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        for (index, still) in stills.enumerated() {
            let png = folder.appending(path: "still.png")
            defer { try? FileManager.default.removeItem(at: png) }
            try media.still(still.file, at: still.at, to: png)
            guard let source = CGImageSourceCreateWithURL(png as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw DriverError("cannot read the still of \(still.name)") }
            // CoreGraphics counts from the bottom left, the layout from the top left.
            let cell = layout.cell(index)
            let fitted = layout.fit(width: image.width, height: image.height)
            let top = cell.y + ContactSheetLayout.labelHeight + fitted.y
            context.draw(image, in: CGRect(x: cell.x + fitted.x, y: layout.height - top - fitted.height,
                                           width: fitted.width, height: fitted.height))
            let label = NSAttributedString(string: still.name, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
            context.textPosition = CGPoint(x: cell.x + 4, y: layout.height - cell.y - ContactSheetLayout.labelHeight + 7)
            CTLineDraw(CTLineCreateWithAttributedString(label), context)
        }
        guard let sheet = context.makeImage(),
              let target = CGImageDestinationCreateWithURL(folder.appending(path: ReviewNames.contactSheet) as CFURL,
                                                           UTType.png.identifier as CFString, 1, nil)
        else { throw DriverError("cannot write the contact sheet") }
        CGImageDestinationAddImage(target, sheet, nil)
        guard CGImageDestinationFinalize(target) else { throw DriverError("cannot write the contact sheet") }
    }
}
