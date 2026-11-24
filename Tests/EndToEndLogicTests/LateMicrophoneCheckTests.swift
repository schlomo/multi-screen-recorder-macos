import Foundation
import Testing
@testable import EndToEndLogic

/// The late-microphone scenario's check of `recording.json` (D80, backlog item 52).
@Suite struct LateMicrophoneCheckTests {
    private static let loopback = "BlackHole2ch_UID"

    private func manifest(_ loopbackDelays: [Double], _ lateDelays: [Double], lateUID: String = "VSD", events: [String] = []) -> JSONValue {
        func file(_ name: String, _ uid: String, _ delays: [Double]) -> JSONValue {
            .object(["name": .string(name), "audioSource": .string(name), "audioSourceUID": .string(uid),
                     "delays": .array(delays.enumerated().map { .object(["at": .number(Double($0.offset) * 10), "delay": .number($0.element)]) })])
        }
        let screen = JSONValue.object(["name": .string("s.mov"), "screen": .string("Screen")])
        return .object([
            "files": .array([screen, file("BlackHole 2ch", Self.loopback, loopbackDelays), file("Apple Virtual Sound Device", lateUID, lateDelays)]),
            "events": .array(events.map { .object(["event": .string($0), "audioSource": .string("Apple Virtual Sound Device")]) }),
        ])
    }

    /// Either input may be the anchor, a race between their files' starts: the other is measured and placed.
    @Test func eitherInputIsTheAnchorAndTheOtherIsMeasured() {
        #expect(LateMicrophoneCheck.failures(manifest: manifest([0], [0, 0.35]), loopbackUID: Self.loopback).isEmpty)
        #expect(LateMicrophoneCheck.failures(manifest: manifest([-0.38], [0]), loopbackUID: Self.loopback).isEmpty)
    }

    @Test func aLateMicrophoneNeverMeasuredFails() {
        #expect(LateMicrophoneCheck.failures(manifest: manifest([0], []), loopbackUID: Self.loopback) == [
            "Apple Virtual Sound Device: no audio delay measured, expected one of 200 to 600 ms against the anchor BlackHole 2ch",
        ])
    }

    @Test func anAudioDelayOutsideTheExpectedRangeFails() {
        #expect(LateMicrophoneCheck.failures(manifest: manifest([0], [0.9]), loopbackUID: Self.loopback) == [
            "Apple Virtual Sound Device: audio delay 900 ms, expected 200 to 600 ms against the anchor BlackHole 2ch",
        ])
    }

    @Test func noAnchorFails() {
        #expect(LateMicrophoneCheck.failures(manifest: manifest([0.1], [0.4]), loopbackUID: Self.loopback) == [
            "no anchor: neither BlackHole 2ch nor Apple Virtual Sound Device lists delays [{at: 0, delay: 0}]",
        ])
    }

    @Test func leavingTheGuideTrackFails() {
        let failures = LateMicrophoneCheck.failures(
            manifest: manifest([0], [0.35], events: ["audio input left the guide track"]), loopbackUID: Self.loopback)
        #expect(failures == ["Apple Virtual Sound Device left the \"Audio inputs\" guide track"])
    }

    @Test func withoutExactlyOneMoreInputItFails() {
        let onlyLoopback = JSONValue.object(["files": .array([.object([
            "name": .string("b.mov"), "audioSource": .string("BlackHole 2ch"), "audioSourceUID": .string(Self.loopback),
            "delays": .array([]),
        ])]), "events": .array([])])
        #expect(LateMicrophoneCheck.failures(manifest: onlyLoopback, loopbackUID: Self.loopback) == [
            "expected the loopback device and one more audio input, each with one file; found BlackHole 2ch",
        ])
    }
}
