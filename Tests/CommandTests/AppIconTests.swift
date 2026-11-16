import Foundation
import Testing

@Suite struct AppIconTests {
    @Test func theCommittedPNGIs1024PixelsSquareWithAlpha() throws {
        let png = try Data(contentsOf: repositoryRoot.appending(path: "assets/icon/app-icon.png"))
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        try #require(png.count >= 33 && Array(png.prefix(8)) == signature, "not a PNG")
        let header = Array(png[8..<33])
        #expect(Array(header[4..<8]) == Array("IHDR".utf8))
        func bigEndian(_ bytes: ArraySlice<UInt8>) -> Int { bytes.reduce(0) { $0 << 8 | Int($1) } }
        #expect(bigEndian(header[8..<12]) == 1024, "width")
        #expect(bigEndian(header[12..<16]) == 1024, "height")
        #expect([4, 6].contains(header[17]), "colour type \(header[17]) has no alpha")
    }

    /// The homepage's favicons are rendered from the app icon (`scripts/render-app-icon`).
    @Test func theHomepagesSVGFaviconIsTheAppIcon() throws {
        let icon = try Data(contentsOf: repositoryRoot.appending(path: "assets/icon/app-icon.svg"))
        #expect(try Data(contentsOf: repositoryRoot.appending(path: "homepage/static/favicon.svg")) == icon)
    }
}
