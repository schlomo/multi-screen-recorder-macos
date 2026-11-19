import Foundation
import Testing
@testable import msr

/// The start window's header draws a slim light frame around the icon's
/// graphite tile in dark mode, following the tile's shape in the icon.
@Suite struct IconTileFrameTests {
    @Test func theFrameFollowsTheTileOfThe48PointIcon() {
        let frame = IconTileFrame(iconSize: 48)
        #expect(abs(frame.inset - 4.7) < 0.05, "\(frame.inset)")
        #expect(abs(frame.cornerRadius - 8.6) < 0.05, "\(frame.cornerRadius)")
        #expect(frame.lineWidth == 1)
        #expect(frame.opacity == 0.25)
    }

    /// The tile's numbers are the icon's: a 300-unit tile with corners of 67 in a view box of 372.82.
    @Test func theTileIsTheIconFilesTile() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let svg = try String(contentsOf: root.appending(path: "assets/icon/app-icon.svg"), encoding: .utf8)
        #expect(svg.contains(#"viewBox="-36.41 -36.41 \#(IconTileFrame.viewBox) \#(IconTileFrame.viewBox)""#))
        #expect(svg.contains(#"<rect x="0" y="0" width="\#(Int(IconTileFrame.tileSize))" height="\#(Int(IconTileFrame.tileSize))" rx="\#(Int(IconTileFrame.tileCornerRadius))""#))
    }
}
