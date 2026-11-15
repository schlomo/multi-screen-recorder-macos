import AppKit
import RecorderLogic

/// The widths of the window's table "What will be recorded". The columns
/// after Source are as wide as their widest possible content in the font the
/// table uses, so nothing moves when the settings or the devices change;
/// Source takes the rest of the window and is as wide as the longest name
/// expected.
enum TableLayout {
    /// The font of a `Text` in the table: SwiftUI's body font.
    static var font: NSFont { NSFont.preferredFont(forTextStyle: .body) }

    static let columnSpacing: CGFloat = 8

    /// The longest source name expected, which Source must hold; a longer one is truncated.
    static let longestSourceName = "MacBook Pro Microphone (default)"

    /// The widest possible content of each column after Source.
    static let samples: [[String]] = [
        ["8888×8888"],
        ["8888×8888"],
        ["8888×8888", "2 channels", "stereo", "cannot be read"],
        ["888.8", "<0.1", "?", "0"],
    ]

    static let sourceWidth = measuredWidth(longestSourceName, WhatWillBeRecorded.columns[0])

    /// Looks like, Drawn at, Records at and GB/h.
    static let fixedColumnWidths: [CGFloat] = samples.enumerated().map { offset, samples in
        measuredWidth(samples + [WhatWillBeRecorded.columns[offset + 1]])
    }

    static let tableWidth = sourceWidth + fixedColumnWidths.reduce(0, +)
        + columnSpacing * CGFloat(WhatWillBeRecorded.columns.count - 1)

    /// The window's width: the table and the window's padding on both sides.
    static let windowWidth = tableWidth + 2 * windowPadding
    static let windowPadding: CGFloat = 20

    /// The width of the widest of `texts` in the table's font, rounded up.
    private static func measuredWidth(_ texts: String...) -> CGFloat {
        measuredWidth(texts)
    }

    private static func measuredWidth(_ texts: [String]) -> CGFloat {
        ceil(texts.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0)
    }
}
