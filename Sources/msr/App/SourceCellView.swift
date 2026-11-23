import RecorderLogic
import SwiftUI

/// A source in the Source column (D55): an icon for its kind, then its
/// number, if it is recorded (a source not recorded keeps the number's
/// width blank), and its name. Its row's mouse-over shows the source's
/// details, its full name first (`SourceDetails`).
struct SourceCellView: View {
    let cell: SourceCell
    /// The digits of the highest number in the table, the width a source not recorded keeps blank.
    var numberDigits = 1

    var body: some View {
        HStack(spacing: TableLayout.iconSpacing) {
            Image(systemName: Self.symbol(cell.kind))
                .frame(width: TableLayout.iconWidth)
                .accessibilityLabel(Self.kindName(cell.kind))
            nameText
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// The number and the name; a source not recorded has no number, and its name starts where the others' do.
    @ViewBuilder private var nameText: some View {
        if let number = cell.number {
            Text("\(number) \(cell.name)")
        } else {
            HStack(spacing: 0) {
                Text(String(repeating: "0", count: numberDigits) + " ").hidden()
                Text(cell.name)
            }
        }
    }

    static func symbol(_ kind: SourceCell.Kind) -> String {
        switch kind {
        case .screen: "display"
        case .camera: "video"
        case .audioInput: "mic"
        case .systemAudio: "speaker.wave.2"
        }
    }

    private static func kindName(_ kind: SourceCell.Kind) -> String {
        switch kind {
        case .screen: "Screen"
        case .camera: "Camera"
        case .audioInput, .systemAudio: "Audio"
        }
    }
}
