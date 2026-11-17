import AppKit
import RecorderLogic
import Testing
@testable import msr

/// The columns after Source are as wide as their widest possible content,
/// measured in the font the table uses, so changing a setting moves
/// nothing; Source is as wide as the names of what is connected.
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
        for text in ["8888×8888", "2 channels", "stereo", "cannot be read", "888.8", "<0.1", "?", "-"] {
            #expect(all.contains(text), Comment(rawValue: text))
        }
    }

    @Test func eachFixedStatusColumnHoldsItsWidestContent() {
        let widest = [["8888×8888", "2 channels", "stereo"], ["888"], ["888.8 GB", "999 MB", "?"],
                      RecordingStatusTable.StateText.allCases.map(\.rawValue), ["-1000 ppm (-9999.9 ms)", "measuring (-9999.9 ms)"]]
        #expect(TableLayout.statusColumnWidths.count == RecordingStatusTable.columns.count - 1)
        for (width, texts) in zip(TableLayout.statusColumnWidths, widest) {
            for text in texts { #expect(width >= measured(text), Comment(rawValue: text)) }
        }
    }

    @Test func theSourceColumnHoldsTheLongestNameWholeWithAnyNumber() {
        let names = ["DELL P3421W", "CalDigit Thunderbolt 3 Audio", "System"]
        #expect(TableLayout.sourceWidth(names: names)
            >= TableLayout.iconWidth + TableLayout.iconSpacing + measured("88 CalDigit Thunderbolt 3 Audio"))
    }

    @Test func theSourceColumnNarrowsToShortNamesButHoldsItsHeader() {
        let short = TableLayout.sourceWidth(names: ["LG", "System"])
        #expect(short < TableLayout.sourceWidth(names: ["CalDigit Thunderbolt 3 Audio"]))
        #expect(short >= measured(WhatWillBeRecorded.columns[0]))
    }
}
