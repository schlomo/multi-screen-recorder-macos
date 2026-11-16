import SwiftUI

/// A vertical stack, leading-aligned, as wide as its children marked
/// `setsTheWidth()` want to be, and never narrower than the others need at
/// least; wider only when its parent offers more. The others get that
/// width, so their text wraps instead of widening the stack: a window
/// built on it is as wide as its table.
struct WidthSettingStack: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(width(of: subviews), proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 0)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }

    private func width(of subviews: Subviews) -> CGFloat {
        subviews.map { subview in
            subview[SetsTheWidth.self]
                ? subview.sizeThatFits(.unspecified).width
                : subview.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
        }.max() ?? 0
    }
}

private struct SetsTheWidth: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// In a `WidthSettingStack`: this child's own width sets the stack's.
    func setsTheWidth() -> some View {
        layoutValue(key: SetsTheWidth.self, value: true)
    }
}
