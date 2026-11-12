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
    private let retina = FrameSize(width: 3456, height: 2234)
    private let uhd = FrameSize(width: 3840, height: 2160)
    private let wuxga = FrameSize(width: 1920, height: 1200)

    @Test func printsWithTheMultiplicationSign() {
        #expect(FrameSize(width: 1670, height: 1080).description == "1670×1080")
    }

    @Test(arguments: [
        (RecordingResolution.native, FrameSize(width: 3456, height: 2234)),
        (.uhd4k, FrameSize(width: 3340, height: 2160)),
        (.p1440, FrameSize(width: 2226, height: 1440)),
        (.p1200, FrameSize(width: 1856, height: 1200)),
        (.p1080, FrameSize(width: 1670, height: 1080)),
        (.p720, FrameSize(width: 1112, height: 720)),
    ])
    func retinaDisplayInEveryResolution(resolution: RecordingResolution, expected: FrameSize) {
        #expect(resolution.frameSize(forDisplay: retina) == expected)
    }

    @Test(arguments: [
        (RecordingResolution.native, FrameSize(width: 3840, height: 2160)),
        (.uhd4k, FrameSize(width: 3840, height: 2160)),
        (.p1440, FrameSize(width: 2560, height: 1440)),
        (.p1200, FrameSize(width: 1920, height: 1080)),
        (.p1080, FrameSize(width: 1920, height: 1080)),
        (.p720, FrameSize(width: 1280, height: 720)),
    ])
    func uhdDisplayInEveryResolution(resolution: RecordingResolution, expected: FrameSize) {
        #expect(resolution.frameSize(forDisplay: uhd) == expected)
    }

    @Test func aWiderBoxLimitsByHeight() {
        #expect(RecordingResolution.p1080.frameSize(forDisplay: wuxga) == FrameSize(width: 1728, height: 1080))
    }

    @Test func neverEnlarges() {
        let small = FrameSize(width: 1280, height: 800)
        #expect(RecordingResolution.uhd4k.frameSize(forDisplay: small) == small)
        #expect(RecordingResolution.p1080.frameSize(forDisplay: small) == small)
    }

    @Test func oddSidesRoundDownToEven() {
        #expect(RecordingResolution.native.frameSize(forDisplay: FrameSize(width: 1367, height: 769))
            == FrameSize(width: 1366, height: 768))
        #expect(RecordingResolution.p1080.frameSize(forDisplay: FrameSize(width: 1001, height: 999))
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
    func aPortraitDisplayIsShrunkIntoTheRotatedBox(resolution: RecordingResolution, expected: FrameSize) {
        let portrait = FrameSize(width: 2160, height: 3840)
        #expect(resolution.frameSize(forDisplay: portrait) == expected)
    }

    @Test func aSquareDisplayUsesTheLandscapeBox() {
        let square = FrameSize(width: 2000, height: 2000)
        #expect(RecordingResolution.p1080.frameSize(forDisplay: square) == FrameSize(width: 1080, height: 1080))
    }

    @Test func keepsProportionsWithinRounding() {
        for resolution in RecordingResolution.allCases {
            let frame = resolution.frameSize(forDisplay: retina)
            let displayRatio = Double(retina.width) / Double(retina.height)
            let frameRatio = Double(frame.width) / Double(frame.height)
            #expect(abs(displayRatio - frameRatio) < 0.01)
        }
    }
}

/// A display file continues while the display's fitted frame size stays the
/// same; when it changes, the file ends and a new one starts (D30).
@Suite struct FrameSizeChangeTests {
    private let uhd = FrameSize(width: 3840, height: 2160)
    private let fiveK = FrameSize(width: 5120, height: 2880)
    private let ultrawide = FrameSize(width: 3440, height: 1440)
    private let fullHD = FrameSize(width: 1920, height: 1080)

    @Test func theExamplesFittedFrameSizes() {
        #expect(RecordingResolution.p1080.frameSize(forDisplay: uhd) == fullHD)
        #expect(RecordingResolution.p1080.frameSize(forDisplay: fiveK) == fullHD)
        #expect(RecordingResolution.p1080.frameSize(forDisplay: ultrawide) == FrameSize(width: 1920, height: 802))
        #expect(RecordingResolution.p1080.frameSize(forDisplay: fullHD) == fullHD)
    }

    @Test func atNativeEveryPixelSizeChangeStartsANewFile() {
        #expect(RecordingResolution.native.displayFileContinues(from: uhd, to: fiveK) == false)
        #expect(RecordingResolution.native.displayFileContinues(from: ultrawide, to: fullHD) == false)
    }

    @Test func at1080pTheSameFittedFrameSizeContinuesTheFile() {
        #expect(RecordingResolution.p1080.displayFileContinues(from: uhd, to: fiveK))
    }

    @Test func at1080pAnotherFittedFrameSizeStartsANewFile() {
        #expect(RecordingResolution.p1080.displayFileContinues(from: ultrawide, to: fullHD) == false)
    }

    @Test func anUnchangedPixelSizeContinuesTheFile() {
        for resolution in RecordingResolution.allCases {
            #expect(resolution.displayFileContinues(from: ultrawide, to: ultrawide))
        }
    }

    @Test func turningADisplayToPortraitStartsANewFile() {
        #expect(RecordingResolution.p1080.displayFileContinues(
            from: uhd, to: FrameSize(width: 2160, height: 3840)) == false)
    }
}
