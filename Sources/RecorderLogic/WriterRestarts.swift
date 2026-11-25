/// A screen's, camera's or audio source's restarts after its writer failed (D88): a failed writer's status is final, so the
/// first restart is at once; a writer failing again within `writerFailedAgainWithin` of its restart waits the
/// back-off, rising, so a broken encoder cannot loop.
struct WriterRestarts: Equatable, Sendable {
    /// When the latest restart's stream started; nil until it has.
    var startedAt: Int64?
    /// The wait should the writer fail again soon.
    var backOff: Duration

    /// The wait before the restart after a writer failure at `now`, and the restarts from then on.
    static func after(
        _ previous: WriterRestarts?, at now: Int64, within: Duration, first: Duration, longest: Duration
    ) -> (wait: Duration, restarts: WriterRestarts) {
        guard let previous, let started = previous.startedAt, now - started < within.nanoseconds else {
            return (.zero, WriterRestarts(backOff: first))
        }
        return (previous.backOff, WriterRestarts(backOff: min(previous.backOff * 2, longest)))
    }
}
