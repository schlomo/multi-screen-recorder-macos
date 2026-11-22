import RecorderLogic
import SwiftUI

/// An audio source's level meter in the status window (D69): a bar of the
/// sample peak on the scale from −60 to 0 dBFS, the peak hold as a mark,
/// each red from −1 dBFS on.
struct LevelMeterView: View {
    let level: AudioLevel

    var body: some View {
        let width = TableLayout.levelMeterWidth
        ZStack(alignment: .leading) {
            Rectangle().fill(.quaternary)
            Rectangle()
                .fill(level.peakIsRed ? Color.red : Color.green)
                .frame(width: width * level.peakFraction)
            if level.holdFraction > 0 {
                Rectangle()
                    .fill(level.holdIsRed ? Color.red : Color.primary)
                    .frame(width: 2)
                    .offset(x: max(0, width * level.holdFraction - 2))
            }
        }
        .frame(width: width, height: TableLayout.levelMeterHeight)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .accessibilityElement()
        .accessibilityLabel("Level")
        .accessibilityValue(Self.text(level))
    }

    /// "−12 dBFS, peak −3 dBFS"; "no sound" for exact zeros.
    static func text(_ level: AudioLevel) -> String {
        guard let peak = level.peakDBFS else { return "no sound" }
        let hold = level.holdDBFS.map { ", peak \(Int($0.rounded())) dBFS" } ?? ""
        return "\(Int(peak.rounded())) dBFS" + hold
    }
}
