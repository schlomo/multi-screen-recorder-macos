import AppKit
import RecorderLogic
import Testing
@testable import msr

/// The widths of the window's table come from the widest possible content,
/// measured in the font the table uses, never from what is connected.
@Suite struct TableLayoutTests {
    private func measured(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: TableLayout.font]).width
    }

    @Test func eachFixedColumnIsAtLeastAsWideAsItsHeaderAndEverySample() {
        #expect(TableLayout.fixedColumnWidths.count == WhatWillBeRecorded.columns.count - 1)
        for (offset, width) in TableLayout.fixedColumnWidths.enumerated() {
            let column = offset + 1
            #expect(width >= measured(WhatWillBeRecorded.columns[column]), "header of column \(column)")
            for sample in TableLayout.samples[offset] {
                #expect(width >= measured(sample), "\(sample) in column \(column)")
            }
        }
    }

    @Test func theSamplesAreTheWidestPossibleContent() {
        let all = TableLayout.samples.flatMap { $0 }
        for text in ["8888×8888", "2 channels", "stereo", "cannot be read", "888.8", "<0.1", "?", "0"] {
            #expect(all.contains(text), Comment(rawValue: text))
        }
    }

    @Test func theSourceColumnHoldsTheLongestExpectedName() {
        #expect(TableLayout.sourceWidth
            >= TableLayout.iconWidth + TableLayout.iconSpacing + measured("88 MacBook Pro Microphone (default)"))
    }

    @Test func theWindowIsAsWideAsTheTable() {
        let spacing = TableLayout.columnSpacing * CGFloat(WhatWillBeRecorded.columns.count - 1)
        #expect(TableLayout.tableWidth == TableLayout.sourceWidth + TableLayout.fixedColumnWidths.reduce(0, +) + spacing
            + 2 * TableLayout.cellPadding)
    }
}
