/// When the screen a change was made to last changed, the way the recorder
/// counts it: its settle time is per screen and starts again with each
/// change of that screen's own place or size, a knock-on one included (on
/// the runner, a connect switched the own screen's mode and moved the
/// virtual screen with it); another screen's change does not count.
public enum ScreenSettling {
    /// The screens as the driver read them at a time, in seconds after the
    /// recording's start: each screen's place and size by its UUID.
    public struct Observation: Sendable, Equatable {
        public var time: Double
        public var screens: [String: String]

        public init(time: Double, screens: [String: String]) {
            self.time = time
            self.screens = screens
        }
    }

    /// The screen's last change, from observations whose first one was
    /// taken before the ask, once it has been unchanged for the settle time
    /// after it; nil while it has not, or has not changed at all. A change
    /// after it had settled belongs to something else.
    public static func lastChange(of screenUUID: String, observations: [Observation], settleTime: Double) -> Double? {
        guard let first = observations.first else { return nil }
        var previous = first.screens[screenUUID]
        var lastChange: Double?
        for observation in observations.dropFirst() {
            if let lastChange, observation.time - lastChange >= settleTime { return lastChange }
            let place = observation.screens[screenUUID]
            if place != previous { lastChange = observation.time }
            previous = place
        }
        return nil
    }
}
