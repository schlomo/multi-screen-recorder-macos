import Foundation
import Testing
@testable import RecorderLogic

/// The recording log starts with the starting situation (D64): the app,
/// the Mac, the settings, "What will be recorded" and the ready check.
@Suite struct RecordingLogStartTests {
    private let dell = ScreenInfo(name: "DELL P3421W", pixelSize: FrameSize(width: 3440, height: 1440),
                                   pointSize: FrameSize(width: 3440, height: 1440), isMain: true, originX: 0, originY: 0)
    private var facts: ReadyCheckFacts {
        ReadyCheckFacts(
            screenRecording: .granted, microphoneGranted: true, screens: .success([dell]),
            audioInputs: .success([AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: true)]),
            outputFolder: .usable(.bytes(120_400_000_000)))
    }

    private func lines() -> [DetailLine.Entry] {
        RecordingLogStart.lines(
            app: "Multi Screen Recorder 0.20261119.1 (abc1234)", recordingFolder: "2026-11-19 12.33.22",
            macOS: "Version 26.1 (Build 25B78)", macModel: "Mac15,8", settings: .defaults, facts: facts)
    }

    @Test func theBlockHasTheSituationInOrder() throws {
        let lines = lines()
        #expect(lines[0] == .init(category: "recorder", message:
            "started: Multi Screen Recorder 0.20261119.1 (abc1234), recording folder 2026-11-19 12.33.22"))
        #expect(lines[1] == .init(category: "recorder", message: "macOS Version 26.1 (Build 25B78), Mac model Mac15,8"))
        let settings = try #require(lines[2].message.wholeMatch(of: /settings: (.*)/)?.1)
        let recorded = try JSONDecoder().decode(RecordingManifest.RecordedSettings.self, from: Data(settings.utf8))
        #expect(recorded == RecordingManifest.RecordedSettings(.defaults))
        let table = WhatWillBeRecorded(settings: .defaults, facts: facts).text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).filter { !$0.isEmpty }
        let readyCheck = ReadyCheck.evaluate(facts, settings: .defaults).text.split(separator: "\n").map(String.init)
        #expect(lines[3...].map(\.category)
            == Array(repeating: "what will be recorded", count: table.count) + ["ready check"]
            + Array(repeating: "ready check", count: readyCheck.count))
        #expect(lines[3..<(3 + table.count)].map(\.message) == table)
        #expect(lines[3 + table.count].message == DetailLine.facts(facts))
        #expect(lines[(4 + table.count)...].map(\.message) == readyCheck)
        #expect(readyCheck.contains { $0.hasPrefix("ok ") })
    }

    @Test func anUnknownMacModelIsSaid() {
        let lines = RecordingLogStart.lines(
            app: "a", recordingFolder: "f", macOS: "Version 26.1 (Build 25B78)", macModel: nil, settings: .defaults, facts: facts)
        #expect(lines[1].message == "macOS Version 26.1 (Build 25B78), Mac model unknown")
    }

    /// Nothing that identifies the person beyond what the files carry.
    @Test func theBlockNamesNoUserOrHost() {
        let text = lines().map(\.message).joined(separator: "\n")
        #expect(!text.contains(NSUserName()))
        #expect(!text.contains(ProcessInfo.processInfo.hostName))
        #expect(!text.contains(NSHomeDirectory()))
    }
}
