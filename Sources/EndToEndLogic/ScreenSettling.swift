/// When the screens have settled after a change the driver made: the first
/// moment all of them, the Mac's own included, have been unchanged for the
/// settle time. A change can knock on to another screen (on the runner, a
/// connect switched the own screen's mode), and each change starts the
/// recorder's settle time again.
public enum ScreenSettling {
    /// The screens as the driver read them at a time, in seconds after the
    /// recording's start: one line per screen, its place and size.
    public struct Observation: Sendable, Equatable {
        public var time: Double
        public var screens: [String]

        public init(time: Double, screens: [String]) {
            self.time = time
            self.screens = screens
        }
    }

    /// The moment the screens settled after a change done at `changeDone`,
    /// from observations from then on; nil while they have not yet. A change
    /// after they had settled belongs to something else.
    public static func settledAt(changeDone: Double, observations: [Observation], settleTime: Double) -> Double? {
        var lastChange = changeDone
        var previous: [String]?
        for observation in observations where observation.time >= changeDone {
            defer { previous = observation.screens }
            if observation.time - lastChange >= settleTime { return lastChange + settleTime }
            if let previous, previous != observation.screens { lastChange = observation.time }
        }
        guard let last = observations.last, last.time - lastChange >= settleTime else { return nil }
        return lastChange + settleTime
    }
}
