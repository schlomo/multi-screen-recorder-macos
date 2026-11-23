/// A camera's picture boxed between black bars in the other orientation (D76):
/// a camera such as the DJI Osmo Pocket offers its frame size in both
/// orientations, and in the orientation it is not set to it delivers its picture
/// between pure black bars, a portrait picture pillarboxed in a landscape
/// frame or a landscape one letterboxed in a portrait frame.
public enum CameraOrientation {
    /// The samples of a frame's luma checked along its long side; the short side's in proportion.
    public static let samplesAlongTheLongSide = 192
    /// How far above the black level a bar's sample may be: bars are pure black, a dark room is not.
    public static let barTolerance: UInt8 = 4
    /// How far the picture's aspect ratio may be from the other orientation's, as a fraction of it.
    public static let aspectTolerance = 0.05
    /// How long a camera's start waits, from its first frame, to tell its picture's orientation before its file starts.
    public static let startCheck = Duration.seconds(1)
    /// The frames in a row that tell the picture's orientation at the start.
    public static let startFrames = 3
    /// How often a recording camera's picture is checked.
    public static let checkInterval = Duration.seconds(5)
    /// How often it is checked while a boxed picture is being confirmed.
    public static let confirmInterval = Duration.milliseconds(500)
    /// How long the picture stays boxed in the other orientation before the camera turns.
    public static let confirmFor = Duration.seconds(2)

    /// A frame's luma, sampled on a grid, row by row.
    public struct Luma: Equatable, Sendable {
        public var width: Int
        public var height: Int
        public var samples: [UInt8]
        /// The luma of black: 16 in video range, 0 in full range.
        public var blackLevel: UInt8

        public init(width: Int, height: Int, samples: [UInt8], blackLevel: UInt8) {
            precondition(samples.count == width * height, "a luma grid of \(width)×\(height) needs \(width * height) samples")
            self.width = width
            self.height = height
            self.samples = samples
            self.blackLevel = blackLevel
        }
    }

    /// The part of a frame between its black bars, in grid samples.
    public struct Picture: Equatable, Sendable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int
    }

    /// The picture between the frame's black bars: whole columns at the left
    /// and right and whole rows at the top and bottom whose every sample is
    /// within `barTolerance` of black; the whole frame without bars; nil for
    /// a frame that is black all over.
    public static func picture(in luma: Luma) -> Picture? {
        let limit = luma.blackLevel &+ barTolerance
        let isBlackColumn = { (x: Int) in (0..<luma.height).allSatisfy { luma.samples[$0 * luma.width + x] <= limit } }
        let isBlackRow = { (y: Int) in luma.samples[(y * luma.width)..<((y + 1) * luma.width)].allSatisfy { $0 <= limit } }
        guard let left = (0..<luma.width).first(where: { !isBlackColumn($0) }) else { return nil }
        let right = (0..<luma.width).last { !isBlackColumn($0) }!
        let top = (0..<luma.height).first { !isBlackRow($0) }!
        let bottom = (0..<luma.height).last { !isBlackRow($0) }!
        return Picture(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    /// Whether `picture` is the other orientation's, boxed in a frame of `luma`'s
    /// size: bars on both sides across the long side, equal within a sample,
    /// none across the short side (a dark first or last row of the picture
    /// allowed), and the picture's aspect ratio within `aspectTolerance` of
    /// the frame turned.
    public static func isBoxedInTheOtherOrientation(_ picture: Picture, in luma: Luma) -> Bool {
        guard luma.width != luma.height else { return false }
        let isLandscape = luma.width > luma.height
        let (start, length, frameLength, across, frameAcross) = isLandscape
            ? (picture.x, picture.width, luma.width, picture.height, luma.height)
            : (picture.y, picture.height, luma.height, picture.width, luma.width)
        let end = frameLength - start - length
        guard start > 0, end > 0, abs(start - end) <= 1, across >= frameAcross - 2 else { return false }
        let turned = Double(luma.height) / Double(luma.width)
        let aspect = Double(picture.width) / Double(picture.height)
        return abs(aspect - turned) <= aspectTolerance * turned
    }

    /// Follows a camera capture's picture: at its start, its first frames
    /// before its file starts; while recording, a frame every
    /// `checkInterval`, and every `confirmInterval` while a boxed picture is
    /// confirmed for `confirmFor`. The same picture, within a sample, every time.
    public struct Watch: Sendable {
        public enum Verdict: Equatable, Sendable {
            /// Still telling the orientation at the start: the frame is not recorded yet.
            case holdBack
            case record
            /// The picture is the other orientation's: the camera is to turn.
            case otherOrientation
        }

        private enum Phase: Sendable {
            case starting(firstFrameAt: Int64?, boxed: Int, unboxed: Int, picture: Picture?)
            case recording(nextCheck: Int64, boxedSince: Int64?, picture: Picture?)
            case turning
        }

        private var phase: Phase = .starting(firstFrameAt: nil, boxed: 0, unboxed: 0, picture: nil)

        public init() {}

        /// Whether the frame at `now` is to be checked.
        public func checks(at now: Int64) -> Bool {
            switch phase {
            case .starting: true
            case .recording(let nextCheck, _, _): now >= nextCheck
            case .turning: false
            }
        }

        /// What to do with a frame at `now`; `luma` its sampled luma, nil for a frame not checked.
        /// A frame black all over, as a camera's first ones often are, tells nothing.
        public mutating func observe(_ luma: Luma?, at now: Int64) -> Verdict {
            let picture = luma.flatMap(CameraOrientation.picture(in:))
            let boxed = luma.flatMap { luma in picture.map { CameraOrientation.isBoxedInTheOtherOrientation($0, in: luma) } } ?? false
            switch phase {
            case .turning:
                return .otherOrientation
            case .starting(let firstFrameAt, var boxedCount, var unboxedCount, let before):
                let first = firstFrameAt ?? now
                if boxed {
                    boxedCount = before.map { Self.isSame(picture!, $0) } == false ? 1 : boxedCount + 1
                    unboxedCount = 0
                } else if picture != nil {
                    boxedCount = 0
                    unboxedCount += 1
                }
                if boxedCount >= CameraOrientation.startFrames {
                    phase = .turning
                    return .otherOrientation
                }
                if unboxedCount >= CameraOrientation.startFrames || now - first >= CameraOrientation.startCheck.nanoseconds {
                    phase = .recording(nextCheck: now + CameraOrientation.checkInterval.nanoseconds, boxedSince: nil, picture: nil)
                    return .record
                }
                phase = .starting(
                    firstFrameAt: first, boxed: boxedCount, unboxed: unboxedCount, picture: boxed ? picture : picture == nil ? before : nil)
                return .holdBack
            case .recording(let nextCheck, let boxedSince, let before):
                guard luma != nil, now >= nextCheck else { return .record }
                guard boxed, let picture else {
                    phase = .recording(nextCheck: now + CameraOrientation.checkInterval.nanoseconds, boxedSince: nil, picture: nil)
                    return .record
                }
                let since = before.map { Self.isSame(picture, $0) } == true ? boxedSince ?? now : now
                if now - since >= CameraOrientation.confirmFor.nanoseconds {
                    phase = .turning
                    return .otherOrientation
                }
                phase = .recording(nextCheck: now + CameraOrientation.confirmInterval.nanoseconds, boxedSince: since, picture: picture)
                return .record
            }
        }

        /// The same picture box, steady within a sample on every edge.
        private static func isSame(_ a: Picture, _ b: Picture) -> Bool {
            abs(a.x - b.x) <= 1 && abs(a.y - b.y) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
        }
    }
}
