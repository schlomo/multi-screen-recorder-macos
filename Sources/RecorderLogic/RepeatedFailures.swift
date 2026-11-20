import Foundation

/// What standard error tells of the events (D65): a failure event once,
/// its repeats counted, and the count when the subject's next event that
/// is no repeat comes, or at Stop. The recording log and the recording
/// manifest keep every event.
public struct RepeatedFailures: Sendable {
    /// A repeat is the same failure event of the same subject with the
    /// same chain of error domains and codes; the error's text does not
    /// count, as it holds the changing file name.
    public struct Key: Hashable, Sendable {
        let event: RecordingEvent.Kind
        let subject: String?
        let codes: [String]

        public init(_ event: RecordingEvent) {
            self.event = event.event
            subject = event.subject
            codes = event.errorDetail.map(Self.codes) ?? []
        }

        private static func codes(_ detail: ErrorDetail) -> [String] {
            ["\(detail.domain) \(detail.code)"] + detail.underlying.flatMap(codes)
        }
    }

    private struct Streak: Sendable {
        let key: Key
        let since: Double
        var count = 0
    }

    /// The failure each subject told last, by subject.
    private var streaks: [String?: Streak] = [:]

    public init() {}

    /// The lines to print for `event`, whose own line is `line`: the count
    /// of the subject's repeats that this event ends, if any, then `line`
    /// unless the event is a repeat.
    public mutating func lines(for event: RecordingEvent, line: String, started: Date, timeZone: TimeZone) -> [String] {
        let key = Key(event)
        if event.event.isFailure, streaks[event.subject]?.key == key {
            streaks[event.subject]?.count += 1
            return []
        }
        let ended = streaks.removeValue(forKey: event.subject).flatMap { countLine($0, at: event.at, started: started, timeZone: timeZone) }
        if event.event.isFailure { streaks[event.subject] = Streak(key: key, since: event.at) }
        return (ended.map { [$0] } ?? []) + [line]
    }

    /// At Stop: the counts of the repeats not told yet.
    public mutating func stop(at seconds: Double, started: Date, timeZone: TimeZone) -> [String] {
        defer { streaks = [:] }
        return streaks.values.sorted { $0.since < $1.since }
            .compactMap { countLine($0, at: seconds, started: started, timeZone: timeZone) }
    }

    /// "22:15:11 +40.0s audio file writer failed repeated 2 times since 22:14:41: Razer Seiren V3 Mini".
    private func countLine(_ streak: Streak, at seconds: Double, started: Date, timeZone: TimeZone) -> String? {
        guard streak.count > 0 else { return nil }
        let times = streak.count == 1 ? "1 time" : "\(streak.count) times"
        return EventLine.time(seconds, started: started, timeZone: timeZone)
            + " \(streak.key.event.rawValue) repeated \(times) since \(EventLine.clock(streak.since, started: started, timeZone: timeZone))"
            + (streak.key.subject.map { ": \($0)" } ?? "")
    }

    /// An event told: its line to the logs, `log`, every time; to people,
    /// `people`, as `lines(for:)` decides, with whether it tells a failure.
    public mutating func tell(
        _ event: RecordingEvent, started: Date, timeZone: TimeZone,
        log: (String) -> Void, people: (_ line: String, _ isFailure: Bool) -> Void
    ) {
        let line = EventLine.text(event, started: started, timeZone: timeZone)
        log(line)
        for shown in lines(for: event, line: line, started: started, timeZone: timeZone) {
            people(shown, shown != line || event.event.isFailure)
        }
    }
}
