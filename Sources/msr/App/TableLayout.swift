import AppKit
import RecorderLogic

/// The widths of the start window's table "What will be recorded" and of
/// the status window's table. The columns after Source are as wide as their
/// widest possible content in the font the tables use, so nothing moves when
/// a setting or, while recording, a state or a size changes; Source is as
/// wide as the longest name of what is connected, whole, and in the start
/// window takes any width the window has beyond the table's.
enum TableLayout {
    /// The font of a `Text` in the table: SwiftUI's body font, with digits
    /// of one width (`monospacedDigit`).
    static var font: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    }

    static let columnSpacing: CGFloat = 8
    /// The space between the table's border and its first and last column.
    static let cellPadding: CGFloat = 6

    /// The kind's icon in Source, and the space after it.
    static let iconWidth: CGFloat = 20
    static let iconSpacing: CGFloat = 6

    /// The widest possible content of each column after Source.
    static let samples: [[String]] = [
        ["8888×8888"],
        ["8888×8888"],
        ["8888×8888", "2 channels", "stereo", "cannot be read"],
        ["888.8", "<0.1", "?", "-"],
    ]

    /// Source's width for these names: each with the widest number, so that
    /// a setting that numbers a source or not moves nothing, after the
    /// kind's icon; and never narrower than the header.
    static func sourceWidth(names: [String]) -> CGFloat {
        max(iconWidth + iconSpacing + measuredWidth(names.map { "88 \($0)" }),
            measuredWidth(WhatWillBeRecorded.columns[0]))
    }

    /// Looks like, Drawn at, Records at and GB/h max.
    static let fixedColumnWidths: [CGFloat] = samples.enumerated().map { offset, samples in
        measuredWidth(samples + [WhatWillBeRecorded.columns[offset + 1]])
    }

    /// The widest possible content of each status column after Source:
    /// Records at, Files, Written, State, every state's text, and Clock drift.
    static let statusSamples: [[String]] = [
        ["8888×8888", "2 channels", "stereo"],
        ["888"],
        ["888.8 GB", "999 MB", "?"],
        RecordingStatusTable.StateText.allCases.map(\.rawValue),
        ["-1000 ppm (-9999.9 ms)", "\(RecordingStatusTable.measuring) (-9999.9 ms)"],
    ]

    /// The status window's columns after Source; its headers, in a bolder
    /// font, may make a column wider still, which does not move either.
    static let statusColumnWidths: [CGFloat] = statusSamples.map(measuredWidth)

    static let windowPadding: CGFloat = 20

    /// The width of the widest of `texts` in the table's font, rounded up.
    private static func measuredWidth(_ texts: String...) -> CGFloat {
        measuredWidth(texts)
    }

    private static func measuredWidth(_ texts: [String]) -> CGFloat {
        ceil(texts.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0)
    }
}
