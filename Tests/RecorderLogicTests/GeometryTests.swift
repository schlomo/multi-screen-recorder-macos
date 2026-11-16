import Testing
@testable import RecorderLogic

@Suite struct RecordingResolutionTests {
    @Test func boxesMatchTheDesign() {
        #expect(RecordingResolution.native.box == nil)
        #expect(RecordingResolution.uhd4k.box == FrameSize(width: 3840, height: 2160))
        #expect(RecordingResolution.p1440.box == FrameSize(width: 2560, height: 1440))
        #expect(RecordingResolution.p1200.box == FrameSize(width: 1920, height: 1200))
        #expect(RecordingResolution.p1080.box == FrameSize(width: 1920, height: 1080))
        #expect(RecordingResolution.p720.box == FrameSize(width: 1280, height: 720))
    }

    @Test func valuesAreTheDocumentedWords() {
        #expect(RecordingResolution.allCases.map(\.rawValue) == ["native", "4k", "1440p", "1200p", "1080p", "720p"])
    }
}

@Suite struct FrameSizeTests {
    /// The built-in screen: looks like 1728×1117, drawn at 3456×2234.
    private let builtIn = FrameSize(width: 1728, height: 1117)
    private let uhd = FrameSize(width: 3840, height: 2160)
    private let wuxga = FrameSize(width: 1920, height: 1200)

    @Test func printsWithTheMultiplicationSign() {
        #expect(FrameSize(width: 1670, height: 1080).description == "1670×1080")
    }

    @Test(arguments: [
        (RecordingResolution.native, FrameSize(width: 1728, height: 1116)),
        (.uhd4k, FrameSize(width: 1728, height: 1116)),
        (.p1440, FrameSize(width: 1728, height: 1116)),
        (.p1200, FrameSize(width: 1728, height: 1116)),
        (.p1080, FrameSize(width: 1670, height: 1080)),
        (.p720, FrameSize(width: 1112, height: 720)),
    ])
    func builtInScreenInEveryResolution(resolution: RecordingResolution, expected: FrameSize) {
        #expect(resolution.frameSize(forLooksLike: builtIn) == expected)
    }

    /// Native is the size macOS shows as "looks like"; the drawn-at size never matters.
    @Test func nativeIsTheLooksLikeSize() {
        #expect(RecordingResolution.native.frameSize(forLooksLike: FrameSize(width: 1728, height: 1117))
            == FrameSize(width: 1728, height: 1116))
        #expect(RecordingResolution.native.frameSize(forLooksLike: FrameSize(width: 3840, height: 2160))
            == FrameSize(width: 3840, height: 2160))
        #expect(RecordingResolution.native.frameSize(forLooksLike: FrameSize(width: 1920, height: 1080))
            == FrameSize(width: 1920, height: 1080))
        #expect(RecordingResolution.p1080.frameSize(forLooksLike: FrameSize(width: 1728, height: 1117))
            == FrameSize(width: 1670, height: 1080))
    }

    @Test(arguments: [
        (RecordingResolution.native, FrameSize(width: 3840, height: 2160)),
        (.uhd4k, FrameSize(width: 3840, height: 2160)),
        (.p1440, FrameSize(width: 2560, height: 1440)),
        (.p1200, FrameSize(width: 1920, height: 1080)),
        (.p1080, FrameSize(width: 1920, height: 1080)),
        (.p720, FrameSize(width: 1280, height: 720)),
    ])
    func uhdScreenInEveryResolution(resolution: RecordingResolution, expected: FrameSize) {
        #expect(resolution.frameSize(forLooksLike: uhd) == expected)
    }

    @Test func aWiderBoxLimitsByHeight() {
        #expect(RecordingResolution.p1080.frameSize(forLooksLike: wuxga) == FrameSize(width: 1728, height: 1080))
    }

    @Test func neverEnlarges() {
        let small = FrameSize(width: 1280, height: 800)
        #expect(RecordingResolution.uhd4k.frameSize(forLooksLike: small) == small)
        #expect(RecordingResolution.p1080.frameSize(forLooksLike: small) == small)
    }

    @Test func oddSidesRoundDownToEven() {
        #expect(RecordingResolution.native.frameSize(forLooksLike: FrameSize(width: 1367, height: 769))
            == FrameSize(width: 1366, height: 768))
        #expect(RecordingResolution.p1080.frameSize(forLooksLike: FrameSize(width: 1001, height: 999))
            == FrameSize(width: 1000, height: 998))
    }

    @Test(arguments: [
        (RecordingResolution.native, FrameSize(width: 2160, height: 3840)),
        (.uhd4k, FrameSize(width: 2160, height: 3840)),
        (.p1440, FrameSize(width: 1440, height: 2560)),
        (.p1200, FrameSize(width: 1080, height: 1920)),
        (.p1080, FrameSize(width: 1080, height: 1920)),
        (.p720, FrameSize(width: 720, height: 1280)),
    ])
    func aPortraitScreenIsShrunkIntoTheRotatedBox(resolution: RecordingResolution, expected: FrameSize) {
        let portrait = FrameSize(width: 2160, height: 3840)
        #expect(resolution.frameSize(forLooksLike: portrait) == expected)
    }

    @Test func aSquareScreenUsesTheLandscapeBox() {
        let square = FrameSize(width: 2000, height: 2000)
        #expect(RecordingResolution.p1080.frameSize(forLooksLike: square) == FrameSize(width: 1080, height: 1080))
    }

    @Test func keepsProportionsWithinRounding() {
        for resolution in RecordingResolution.allCases {
            let frame = resolution.frameSize(forLooksLike: builtIn)
            let screenRatio = Double(builtIn.width) / Double(builtIn.height)
            let frameRatio = Double(frame.width) / Double(frame.height)
            #expect(abs(screenRatio - frameRatio) < 0.01)
        }
    }
}

/// A screen file continues while the screen's frame size, from its looks-like
/// size, stays the same; when it changes, the file ends and a new one starts (D30).
@Suite struct FrameSizeChangeTests {
    private let uhd = FrameSize(width: 3840, height: 2160)
    private let fiveK = FrameSize(width: 5120, height: 2880)
    private let ultrawide = FrameSize(width: 3440, height: 1440)
    private let fullHD = FrameSize(width: 1920, height: 1080)

    @Test func theExamplesFittedFrameSizes() {
        #expect(RecordingResolution.p1080.frameSize(forLooksLike: uhd) == fullHD)
        #expect(RecordingResolution.p1080.frameSize(forLooksLike: fiveK) == fullHD)
        #expect(RecordingResolution.p1080.frameSize(forLooksLike: ultrawide) == FrameSize(width: 1920, height: 802))
        #expect(RecordingResolution.p1080.frameSize(forLooksLike: fullHD) == fullHD)
    }

    @Test func atNativeEveryLooksLikeSizeChangeStartsANewFile() {
        #expect(RecordingResolution.native.screenFileContinues(from: uhd, to: fiveK) == false)
        #expect(RecordingResolution.native.screenFileContinues(from: ultrawide, to: fullHD) == false)
    }

    @Test func at1080pTheSameFittedFrameSizeContinuesTheFile() {
        #expect(RecordingResolution.p1080.screenFileContinues(from: uhd, to: fiveK))
    }

    @Test func at1080pAnotherFittedFrameSizeStartsANewFile() {
        #expect(RecordingResolution.p1080.screenFileContinues(from: ultrawide, to: fullHD) == false)
    }

    @Test func anUnchangedLooksLikeSizeContinuesTheFile() {
        for resolution in RecordingResolution.allCases {
            #expect(resolution.screenFileContinues(from: ultrawide, to: ultrawide))
        }
    }

    @Test func turningAScreenToPortraitStartsANewFile() {
        #expect(RecordingResolution.p1080.screenFileContinues(
            from: uhd, to: FrameSize(width: 2160, height: 3840)) == false)
    }
}
