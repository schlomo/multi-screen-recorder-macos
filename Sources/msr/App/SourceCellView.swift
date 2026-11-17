import RecorderLogic
import SwiftUI

/// A source in the Source column (D55): an icon for its kind, then its
/// number, if it is recorded (an audio source not recorded keeps the
/// number's width blank), and its name.
struct SourceCellView: View {
    let cell: SourceCell

    var body: some View {
        HStack(spacing: TableLayout.iconSpacing) {
            Image(systemName: Self.symbol(cell.kind))
                .frame(width: TableLayout.iconWidth)
                .accessibilityLabel(Self.kindName(cell.kind))
            nameText
                .lineLimit(1)
                .truncationMode(.middle)
                .help(cell.text)
        }
    }

    /// The number and the name; an audio source not recorded has no number, and its name starts where the others' do.
    @ViewBuilder private var nameText: some View {
        if let number = cell.number {
            Text("\(number) \(cell.name)")
        } else if cell.kind == .screen {
            Text(cell.name)
        } else {
            HStack(spacing: 0) {
                Text("0 ").hidden()
                Text(cell.name)
            }
        }
    }

    static func symbol(_ kind: SourceCell.Kind) -> String {
        switch kind {
        case .screen: "display"
        case .audioInput: "mic"
        case .systemAudio: "speaker.wave.2"
        }
    }

    private static func kindName(_ kind: SourceCell.Kind) -> String {
        switch kind {
        case .screen: "Screen"
        case .audioInput, .systemAudio: "Audio"
        }
    }
}
