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

    private func lines() throws -> [DetailLine.Entry] {
        try RecordingLogStart.lines(
            app: "Multi Screen Recorder 0.20261119.1 (abc1234)", recordingFolder: "2026-11-19 12.33.22",
            macOS: "Version 26.1 (Build 25B78)", macModel: "Mac15,8", settings: .defaults, facts: facts)
    }

    @Test func theBlockHasTheSituationInOrder() throws {
        let all = try lines()
        #expect(all[0] == .init(category: "recorder", message:
            "started: Multi Screen Recorder 0.20261119.1 (abc1234), recording folder 2026-11-19 12.33.22"))
        #expect(all[1] == .init(category: "recorder", message: "macOS Version 26.1 (Build 25B78), Mac model Mac15,8"))
        // The full effective settings, as `msr settings` prints them.
        let settings: [String] = String(decoding: try Settings.defaults.jsonData(), as: UTF8.self)
            .split(separator: "\n").map(String.init)
        let settingsEntries: [DetailLine.Entry] = settings.map { DetailLine.Entry(category: "settings", message: $0) }
        #expect(Array(all[2..<(2 + settings.count)]) == settingsEntries)
        #expect(settings.contains { $0.contains("outputFolder") })
        #expect(settings.contains { $0.contains("lowDiskWarningMinutes") })
        let rest: [DetailLine.Entry] = Array(all[(2 + settings.count)...])
        let table: [String] = WhatWillBeRecorded(settings: .defaults, facts: facts).text
            .split(separator: "\n").map(String.init)
        let readyCheck: [String] = ReadyCheck.evaluate(facts, settings: .defaults).text.split(separator: "\n").map(String.init)
        let categories: [String] = Array(repeating: "what will be recorded", count: table.count)
            + Array(repeating: "ready check", count: readyCheck.count + 1)
        #expect(rest.map { $0.category } == categories)
        #expect(rest[..<table.count].map { $0.message } == table)
        #expect(rest[table.count].message == DetailLine.facts(facts, resolution: Settings.defaults.effectiveResolution, limitCameras: true))
        #expect(rest[(1 + table.count)...].map { $0.message } == readyCheck)
        #expect(readyCheck.contains { $0.hasPrefix("ok ") })
    }

    @Test func anUnknownMacModelIsSaid() throws {
        let lines = try RecordingLogStart.lines(
            app: "a", recordingFolder: "f", macOS: "Version 26.1 (Build 25B78)", macModel: nil, settings: .defaults, facts: facts)
        #expect(lines[1].message == "macOS Version 26.1 (Build 25B78), Mac model unknown")
    }

    /// Nothing that identifies the person beyond what the files carry.
    @Test func theBlockNamesNoUserOrHost() throws {
        let text = try lines().map(\.message).joined(separator: "\n")
        #expect(!text.contains(NSUserName()))
        #expect(!text.contains(ProcessInfo.processInfo.hostName))
        #expect(!text.contains(NSHomeDirectory()))
    }
}
