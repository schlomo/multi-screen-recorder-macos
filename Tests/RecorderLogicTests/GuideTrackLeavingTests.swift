import Testing
@testable import RecorderLogic

/// An audio input clearly late leaves the "Audio inputs" guide track (D79).
@Suite struct GuideTrackLeavingTests {
    @Test func theFirstClearWindowDecides() {
        var leaving = GuideTrackLeaving()
        leaving.add(0.5, file: "late.mov", reference: "r.mov")
        leaving.add(0.02, file: "close.mov", reference: "r.mov")
        #expect(leaving.leaving(reference: "r.mov") == ["late.mov": 0.5])
        // Later windows change nothing: neither a second look at the late file, nor bring the close one out.
        leaving.add(0, file: "late.mov", reference: "r.mov")
        leaving.add(0.6, file: "close.mov", reference: "r.mov")
        #expect(leaving.leaving(reference: "r.mov").isEmpty)
    }

    @Test func atOrBelowTheLimitAnInputStays() {
        var leaving = GuideTrackLeaving()
        leaving.add(RecorderValues.guideDelayLimit, file: "a.mov", reference: "r.mov")
        leaving.add(0.05, file: "b.mov", reference: "r.mov")
        #expect(leaving.leaving(reference: "r.mov").isEmpty)
        #expect(RecorderValues.guideDelayLimit == 0.1)
    }

    /// Normalized as the audio delays are: a late reference makes the others early, and neither it nor the
    /// earliest leaves.
    @Test func theReferenceAndTheEarliestNeverLeave() {
        var leaving = GuideTrackLeaving()
        leaving.add(-0.5, file: "early.mov", reference: "r.mov")
        #expect(leaving.leaving(reference: "r.mov").isEmpty)
        leaving.add(-0.3, file: "middle.mov", reference: "r.mov")
        #expect(leaving.leaving(reference: "r.mov") == ["middle.mov": 0.2])
    }

    /// A file that left stays out; the input's next file is a file of its own, back until measured.
    @Test func aFileThatLeftStaysOutAndTheNextFileStartsBack() {
        var leaving = GuideTrackLeaving()
        leaving.add(0.5, file: "a1.mov", reference: "r.mov")
        #expect(leaving.leaving(reference: "r.mov") == ["a1.mov": 0.5])
        #expect(leaving.hasLeft("a1.mov"))
        #expect(!leaving.hasLeft("a2.mov"))
        leaving.add(0.5, file: "a2.mov", reference: "r.mov")
        #expect(leaving.leaving(reference: "r.mov") == ["a2.mov": 0.5])
        // A new reference file measures afresh, but a file that left never comes back.
        leaving.add(0, file: "a1.mov", reference: "r2.mov")
        #expect(leaving.leaving(reference: "r2.mov").isEmpty)
        #expect(leaving.hasLeft("a1.mov"))
    }
}
