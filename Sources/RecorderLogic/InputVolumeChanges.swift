/// An audio input's input volume as the recording manifest tells it (D69):
/// a change, from the status window's slider, a knob or another app, is the
/// event `audio input volume changed` once the volume held still for the
/// settle time, from the volume told before to the new one, at the time it
/// reached it. Volumes are 0 to 1, to the thousandth; times are
/// nanoseconds on the shared clock.
public struct InputVolumeChanges: Sendable {
    public let settleTime: Int64
    /// The volume told last, or read at the start; nil when none was read yet.
    private var told: Double?
    /// The volume read last and when it became that, while it differs from the one told.
    private var latest: (volume: Double, since: Int64)?

    /// `volume`: the input volume at the start, nil when it cannot be read.
    public init(volume: Double?, settleTime: Duration = RecorderValues.inputVolumeSettleTime) {
        told = volume.map(Self.rounded)
        self.settleTime = settleTime.nanoseconds
    }

    /// The volume as read now.
    public mutating func observe(_ volume: Double, at now: Int64) {
        let volume = Self.rounded(volume)
        guard let told else {
            self.told = volume
            return
        }
        if volume == told {
            latest = nil
        } else if latest?.volume != volume {
            latest = (volume, now)
        }
    }

    public func nextDueTime() -> Int64? {
        latest.map { $0.since + settleTime }
    }

    /// The event, once the volume held still for the settle time.
    public mutating func due(at now: Int64, audioSource: String) -> RecordingEvent? {
        guard let latest, now >= latest.since + settleTime else { return nil }
        return flush(audioSource: audioSource)
    }

    /// The event of a change not told yet, whether it held still or not: at the end.
    public mutating func flush(audioSource: String) -> RecordingEvent? {
        guard let latest else { return nil }
        var event = RecordingEvent(at: latest.since, event: .audioInputVolumeChanged, audioSource: audioSource)
        event.from = told.map(RecordingEvent.Value.volume)
        event.to = .volume(latest.volume)
        told = latest.volume
        self.latest = nil
        return event
    }

    /// A volume as the recording manifest gives it: from 0 to 1, to the thousandth.
    public static func rounded(_ volume: Double) -> Double {
        (min(1, max(0, volume)) * 1000).rounded() / 1000
    }
}
