import Testing
@testable import RecorderLogic

@Suite struct CameraOrientationTests {
    private static let second: Int64 = 1_000_000_000

    /// A grid of `width`×`height` with a picture of noisy mid-grey luma in
    /// `picture` (x, y, width, height) and `outside` elsewhere.
    static func luma(
        _ width: Int, _ height: Int, picture: (Int, Int, Int, Int), outside: (Int, Int) -> UInt8 = { _, _ in 16 }
    ) -> CameraOrientation.Luma {
        var generator = SeededRandom(seed: 1)
        var samples = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let inside = x >= picture.0 && x < picture.0 + picture.2 && y >= picture.1 && y < picture.1 + picture.3
                samples[y * width + x] = inside ? UInt8.random(in: 40...200, using: &generator) : outside(x, y)
            }
        }
        return CameraOrientation.Luma(width: width, height: height, samples: samples, blackLevel: 16)
    }

    /// The Osmo set to portrait in a 1920×1080 frame: a 9:16 picture between black bars, 192×108 samples.
    static let pillarboxed = luma(192, 108, picture: (66, 0, 61, 108))
    /// The Osmo set to landscape in a 1080×1920 frame: a 16:9 picture between black bars.
    static let letterboxed = luma(108, 192, picture: (0, 66, 108, 61))
    static let fullFrame = luma(192, 108, picture: (0, 0, 192, 108))

    @Test func aPortraitPicturePillarboxedInALandscapeFrameIsTheOtherOrientation() throws {
        let picture = try #require(CameraOrientation.picture(in: Self.pillarboxed))
        #expect(picture == CameraOrientation.Picture(x: 66, y: 0, width: 61, height: 108))
        #expect(CameraOrientation.isBoxedInTheOtherOrientation(picture, in: Self.pillarboxed))
    }

    @Test func aLandscapePictureLetterboxedInAPortraitFrameIsTheOtherOrientation() throws {
        let picture = try #require(CameraOrientation.picture(in: Self.letterboxed))
        #expect(CameraOrientation.isBoxedInTheOtherOrientation(picture, in: Self.letterboxed))
    }

    @Test func aFullFrameAndABlackFrameAreNot() throws {
        let picture = try #require(CameraOrientation.picture(in: Self.fullFrame))
        #expect(!CameraOrientation.isBoxedInTheOtherOrientation(picture, in: Self.fullFrame))
        #expect(CameraOrientation.picture(in: Self.luma(192, 108, picture: (0, 0, 0, 0))) == nil)
    }

    /// Dark sides that are not pure black, as a dark room's, are no bars.
    @Test func aDarkRoomIsNoBars() throws {
        var generator = SeededRandom(seed: 9)
        let dark = (0..<(192 * 108)).map { _ in UInt8.random(in: 16...30, using: &generator) }
        let room = Self.luma(192, 108, picture: (66, 0, 61, 108)) { x, y in dark[y * 192 + x] }
        let picture = try #require(CameraOrientation.picture(in: room))
        #expect(!CameraOrientation.isBoxedInTheOtherOrientation(picture, in: room))
    }

    /// Bars of another orientation's picture, such as a 4:3 one pillarboxed, are not the other orientation.
    @Test func aPictureOfAnotherAspectRatioIsNot() throws {
        let fourByThree = Self.luma(192, 108, picture: (24, 0, 144, 108))
        let picture = try #require(CameraOrientation.picture(in: fourByThree))
        #expect(!CameraOrientation.isBoxedInTheOtherOrientation(picture, in: fourByThree))
        let letterboxedInLandscape = Self.luma(192, 108, picture: (0, 20, 192, 68))
        #expect(!CameraOrientation.isBoxedInTheOtherOrientation(try #require(CameraOrientation.picture(in: letterboxedInLandscape)), in: letterboxedInLandscape))
    }

    @Test func atTheStartThreeBoxedFramesTurnTheCameraBeforeItsFile() {
        var watch = CameraOrientation.Watch()
        let black = Self.luma(192, 108, picture: (0, 0, 0, 0))
        #expect(watch.observe(black, at: 0) == .holdBack)
        #expect(watch.observe(Self.pillarboxed, at: Self.second / 30) == .holdBack)
        #expect(watch.observe(Self.pillarboxed, at: 2 * Self.second / 30) == .holdBack)
        #expect(watch.observe(Self.pillarboxed, at: 3 * Self.second / 30) == .otherOrientation)
        #expect(!watch.checks(at: Self.second))
    }

    @Test func atTheStartAFullPictureIsRecordedAndSoIsAnUnclearOneAfterASecond() {
        var full = CameraOrientation.Watch()
        #expect(full.observe(Self.fullFrame, at: 0) == .holdBack)
        #expect(full.observe(Self.fullFrame, at: 1) == .holdBack)
        #expect(full.observe(Self.fullFrame, at: 2) == .record)
        var black = CameraOrientation.Watch()
        let dark = Self.luma(192, 108, picture: (0, 0, 0, 0))
        #expect(black.observe(dark, at: 0) == .holdBack)
        #expect(black.observe(dark, at: Self.second - 1) == .holdBack)
        #expect(black.observe(dark, at: Self.second) == .record)
    }

    @Test func whileRecordingABoxedPictureForTwoSecondsTurnsTheCamera() {
        var watch = CameraOrientation.Watch()
        for frame in -2...0 { _ = watch.observe(Self.fullFrame, at: Int64(frame)) }
        #expect(!watch.checks(at: 4 * Self.second))
        #expect(watch.checks(at: 5 * Self.second))
        #expect(watch.observe(Self.pillarboxed, at: 5 * Self.second) == .record)
        #expect(watch.checks(at: 5 * Self.second + Self.second / 2))
        #expect(watch.observe(Self.pillarboxed, at: 6 * Self.second) == .record)
        #expect(watch.observe(Self.pillarboxed, at: 7 * Self.second) == .otherOrientation)
    }

    @Test func whileRecordingAnInterruptedBoxStartsTheTwoSecondsOver() {
        var watch = CameraOrientation.Watch()
        for frame in -2...0 { _ = watch.observe(Self.fullFrame, at: Int64(frame)) }
        #expect(watch.observe(Self.pillarboxed, at: 5 * Self.second) == .record)
        #expect(watch.observe(Self.fullFrame, at: 6 * Self.second) == .record)
        #expect(!watch.checks(at: 7 * Self.second))
        #expect(watch.observe(Self.pillarboxed, at: 11 * Self.second) == .record)
        #expect(watch.observe(Self.pillarboxed, at: 12 * Self.second) == .record)
        #expect(watch.observe(Self.pillarboxed, at: 13 * Self.second) == .otherOrientation)
    }
}
