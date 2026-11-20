/// Where the stills of a contact sheet go: one cell per screen file, rows
/// of up to `maximumColumns`, each cell a label strip above a still fitted
/// into it, keeping its shape. Pixels, from the top left.
public struct ContactSheetLayout: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public var x: Int
        public var y: Int
    }

    public struct Rect: Sendable, Equatable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int
    }

    public static let maximumColumns = 3
    public static let stillWidth = 480
    public static let stillHeight = 270
    public static let labelHeight = 24

    public let count: Int
    public let columns: Int
    public let rows: Int

    public init(count: Int) {
        self.count = count
        columns = max(1, min(count, Self.maximumColumns))
        rows = max(1, (count + columns - 1) / columns)
    }

    public var cellHeight: Int { Self.labelHeight + Self.stillHeight }
    public var width: Int { columns * Self.stillWidth }
    public var height: Int { rows * cellHeight }

    /// The top left of cell `index`: its label strip starts there.
    public func cell(_ index: Int) -> Point {
        Point(x: index % columns * Self.stillWidth, y: index / columns * cellHeight)
    }

    /// A still of this size, fitted into the still's area of a cell: its
    /// place relative to that area's top left.
    public func fit(width: Int, height: Int) -> Rect {
        let scale = min(Double(Self.stillWidth) / Double(width), Double(Self.stillHeight) / Double(height))
        let fittedWidth = Int((Double(width) * scale).rounded())
        let fittedHeight = Int((Double(height) * scale).rounded())
        return Rect(x: (Self.stillWidth - fittedWidth) / 2, y: (Self.stillHeight - fittedHeight) / 2,
                    width: fittedWidth, height: fittedHeight)
    }
}
