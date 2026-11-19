import EndToEndLogic
import Foundation
import Synchronization

/// Reads every screen's place and size every 20 ms on a thread of its own,
/// from before a change is asked until it is stopped, so that the changed
/// screen's last change can be found once its UUID is known.
final class ScreenWatch: Sendable {
    private let readings = Mutex<[(time: Date, screens: [String: String])]>([])
    private let stopped = Atomic<Bool>(false)

    init() {
        readings.withLock { $0.append((Date(), Machine.screenPlaces())) }
        Thread.detachNewThread { [self] in
            while !stopped.load(ordering: .acquiring) {
                Thread.sleep(forTimeInterval: 0.02)
                let reading = (time: Date(), screens: Machine.screenPlaces())
                readings.withLock { $0.append(reading) }
            }
        }
    }

    func stop() { stopped.store(true, ordering: .releasing) }

    /// The readings so far, their times in seconds after `reference`.
    func observations(since reference: Date) -> [ScreenSettling.Observation] {
        readings.withLock { readings in
            readings.map { .init(time: $0.time.timeIntervalSince(reference), screens: $0.screens) }
        }
    }
}
