import RecorderLogic
import SwiftUI

/// A source in the Source column (D55): an icon for its kind, then its
/// number, if it is recorded, and its name.
struct SourceCellView: View {
    let cell: SourceCell

    var body: some View {
        HStack(spacing: TableLayout.iconSpacing) {
            Image(systemName: Self.symbol(cell.kind))
                .frame(width: TableLayout.iconWidth)
                .accessibilityLabel(Self.kindName(cell.kind))
            Text(cell.number.map { "\($0) \(cell.name)" } ?? cell.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(cell.text)
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
