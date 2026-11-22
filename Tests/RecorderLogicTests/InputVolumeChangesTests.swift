import Testing
@testable import RecorderLogic

@Suite struct InputVolumeChangesTests {
    private let millisecond: Int64 = 1_000_000

    @Test func aChangeHeldStillForTheSettleTimeIsOneEvent() throws {
        var changes = InputVolumeChanges(volume: 0.5)
        changes.observe(0.6, at: 1000 * millisecond)
        changes.observe(0.7, at: 1200 * millisecond)
        #expect(changes.nextDueTime() == 1700 * millisecond)
        #expect(changes.due(at: 1699 * millisecond, audioSource: "Razer") == nil)
        let due = changes.due(at: 1700 * millisecond, audioSource: "Razer")
        let event = try #require(due)
        #expect(event.event == .audioInputVolumeChanged)
        #expect(event.audioSource == "Razer")
        #expect(event.at == 1.2)
        #expect(event.from == .volume(0.5))
        #expect(event.to == .volume(0.7))
        #expect(changes.nextDueTime() == nil)
        #expect(changes.due(at: 5000 * millisecond, audioSource: "Razer") == nil)
    }

    @Test func aVolumeReadAgainUnchangedDoesNotStartTheSettleTimeOver() {
        var changes = InputVolumeChanges(volume: 0.5)
        changes.observe(0.6, at: 1000 * millisecond)
        changes.observe(0.6, at: 1400 * millisecond)
        #expect(changes.nextDueTime() == 1500 * millisecond)
    }

    @Test func aChangeBackToTheVolumeToldIsNoEvent() {
        var changes = InputVolumeChanges(volume: 0.5)
        changes.observe(0.6, at: 1000 * millisecond)
        changes.observe(0.5, at: 1100 * millisecond)
        #expect(changes.due(at: 2000 * millisecond, audioSource: "Razer") == nil)
        #expect(changes.nextDueTime() == nil)
    }

    @Test func volumesAreToTheThousandthSoJitterBelowItIsNoChange() {
        var changes = InputVolumeChanges(volume: 0.5)
        changes.observe(0.50004, at: 1000 * millisecond)
        #expect(changes.nextDueTime() == nil)
        #expect(InputVolumeChanges.rounded(0.12345) == 0.123)
        #expect(InputVolumeChanges.rounded(1.2) == 1)
        #expect(InputVolumeChanges.rounded(-0.1) == 0)
    }

    @Test func atTheEndAChangeNotHeldStillYetIsTold() throws {
        var changes = InputVolumeChanges(volume: 0.5)
        changes.observe(0.25, at: 1000 * millisecond)
        let flushed = changes.flush(audioSource: "Razer")
        let event = try #require(flushed)
        #expect(event.at == 1)
        #expect(event.to == .volume(0.25))
        #expect(changes.flush(audioSource: "Razer") == nil)
    }

    @Test func withoutAVolumeAtTheStartTheFirstOneReadIsNoChange() {
        var changes = InputVolumeChanges(volume: nil)
        changes.observe(0.3, at: 1000 * millisecond)
        #expect(changes.due(at: 2000 * millisecond, audioSource: "Razer") == nil)
        changes.observe(0.4, at: 3000 * millisecond)
        #expect(changes.due(at: 4000 * millisecond, audioSource: "Razer")?.from == .volume(0.3))
    }
}
