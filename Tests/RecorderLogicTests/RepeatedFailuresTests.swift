import Foundation
import Testing
@testable import RecorderLogic

/// Standard error tells a failure once and counts its repeats (D65).
@Suite struct RepeatedFailuresTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let start = Date(timeIntervalSince1970: 1_794_777_271)  // 2026-11-15 22:14:31 in Berlin

    private func writerFailed(at seconds: Int64, file: String, code: Int = 513, source: String = "Razer Seiren V3 Mini") -> RecordingEvent {
        var event = RecordingEvent(at: seconds * 1_000_000_000, event: .audioFileWriterFailed, audioSource: source)
        let system = NSError(domain: NSCocoaErrorDomain, code: code, userInfo: [
            NSLocalizedDescriptionKey: "You don’t have permission to save the file “\(file)”."])
        event.errorDetail = ErrorDetail(message: "cannot start writing \(file)", underlying: system)
        return event
    }

    private func lines(_ events: [RecordingEvent], stopAt: Double? = nil) -> [String] {
        var repeats = RepeatedFailures()
        var printed = events.flatMap { event in
            repeats.lines(for: event, line: EventLine.text(event, started: start, timeZone: berlin), started: start, timeZone: berlin)
        }
        if let stopAt { printed += repeats.stop(at: stopAt, started: start, timeZone: berlin) }
        return printed
    }

    @Test func theSameCodesWithAnotherTextAreARepeat() {
        let first = writerFailed(at: 10, file: "a.mov")
        #expect(RepeatedFailures.Key(first) == RepeatedFailures.Key(writerFailed(at: 20, file: "b.mov")))
        #expect(RepeatedFailures.Key(first) != RepeatedFailures.Key(writerFailed(at: 20, file: "a.mov", code: 640)))
        #expect(RepeatedFailures.Key(first) != RepeatedFailures.Key(writerFailed(at: 20, file: "a.mov", source: "BRIO")))
        var otherEvent = first
        otherEvent.event = .audioInputFailed
        #expect(RepeatedFailures.Key(first) != RepeatedFailures.Key(otherEvent))
    }

    @Test func repeatsAreCountedAndToldWhenTheSubjectRecovers() {
        let printed = lines([
            writerFailed(at: 10, file: "a.mov"), writerFailed(at: 20, file: "b.mov"), writerFailed(at: 30, file: "c.mov"),
            RecordingEvent(at: 40_000_000_000, event: .audioInputConnected, audioSource: "Razer Seiren V3 Mini"),
        ])
        #expect(printed == [
            EventLine.text(writerFailed(at: 10, file: "a.mov"), started: start, timeZone: berlin),
            "22:15:11 +40.0s audio file writer failed repeated 2 times since 22:14:41: Razer Seiren V3 Mini",
            "22:15:11 +40.0s audio input connected: Razer Seiren V3 Mini",
        ])
    }

    @Test func aDifferentFailureEndsTheRunAndIsTold() {
        let printed = lines([writerFailed(at: 10, file: "a.mov"), writerFailed(at: 20, file: "b.mov"), writerFailed(at: 30, file: "c.mov", code: 640)])
        #expect(printed.count == 3)
        #expect(printed[1] == "22:15:01 +30.0s audio file writer failed repeated 1 time since 22:14:41: Razer Seiren V3 Mini")
        #expect(printed[2].hasPrefix("22:15:01 +30.0s audio file writer failed: Razer Seiren V3 Mini (cannot start writing c.mov"))
    }

    @Test func theCountIsToldAtStop() {
        let printed = lines([writerFailed(at: 10, file: "a.mov"), writerFailed(at: 20, file: "b.mov")], stopAt: 25)
        #expect(printed.last == "22:14:56 +25.0s audio file writer failed repeated 1 time since 22:14:41: Razer Seiren V3 Mini")
    }

    @Test func noRepeatNoCountLine() {
        let failed = writerFailed(at: 10, file: "a.mov")
        let recovered = RecordingEvent(at: 40_000_000_000, event: .audioInputConnected, audioSource: "Razer Seiren V3 Mini")
        #expect(lines([failed, recovered], stopAt: 50).count == 2)
        #expect(lines([failed], stopAt: 50).count == 1)
    }

    @Test func anotherSubjectsEventsDoNotEndTheRun() {
        let printed = lines([
            writerFailed(at: 10, file: "a.mov"), writerFailed(at: 12, file: "x.mov", source: "BRIO"),
            writerFailed(at: 20, file: "b.mov"), writerFailed(at: 22, file: "y.mov", source: "BRIO"),
            RecordingEvent(at: 30_000_000_000, event: .screenConnected, screen: "LG"),
        ], stopAt: 40)
        #expect(printed.count == 5)
        #expect(printed.suffix(2).sorted() == [
            "22:15:11 +40.0s audio file writer failed repeated 1 time since 22:14:41: Razer Seiren V3 Mini",
            "22:15:11 +40.0s audio file writer failed repeated 1 time since 22:14:43: BRIO",
        ])
    }

    @Test func eventsThatAreNoFailureNeverRepeat() {
        let sleep = RecordingEvent(at: 0, event: .sleep)
        #expect(lines([sleep, sleep, sleep]).count == 3)
    }

    /// The logs get every event's line; people get the first failure, the count and the recovery.
    @Test func theLogGetsEveryLine() {
        var repeats = RepeatedFailures()
        var logged: [String] = []
        var shown: [(String, Bool)] = []
        let events = [writerFailed(at: 10, file: "a.mov"), writerFailed(at: 20, file: "b.mov"),
                      RecordingEvent(at: 40_000_000_000, event: .audioInputConnected, audioSource: "Razer Seiren V3 Mini")]
        for event in events {
            repeats.tell(event, started: start, timeZone: berlin, log: { logged.append($0) }, people: { shown.append(($0, $1)) })
        }
        #expect(logged == events.map { EventLine.text($0, started: start, timeZone: berlin) })
        #expect(shown.map(\.0) == [logged[0], "22:15:11 +40.0s audio file writer failed repeated 1 time since 22:14:41: Razer Seiren V3 Mini", logged[2]])
        #expect(shown.map(\.1) == [true, true, false])
    }
}
