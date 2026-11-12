import Testing
@testable import RecorderLogic

@Suite struct WhatWillBeRecordedTests {
    private static let designFolder = OutputFolderProbe.usable(.bytes(3_100_000_000))

    private func section(
        _ edit: (inout Settings) -> Void = { _ in },
        displays: Result<[DisplayInfo], DeviceReadError> = .success(DesignExample.displays),
        audioInputs: [AudioInputInfo] = DesignExample.audioInputs,
        outputFolder: OutputFolderProbe? = designFolder
    ) -> WhatWillBeRecorded {
        var settings = Settings.defaults
        edit(&settings)
        return WhatWillBeRecorded(settings: settings, displays: displays, audioInputs: audioInputs, outputFolder: outputFolder)
    }

    @Test func theDefaultsWithTheDesignsDevices() {
        #expect(section() == WhatWillBeRecorded(
            displaysError: nil,
            displays: [
                .init(number: 1, name: "Built-in Retina Display", looksLike: "1728×1117", drawnAt: "3456×2234",
                      recordsAt: "1670×1080", gigabytesPerHour: "0.9"),
                .init(number: 2, name: "LG HDR 4K", looksLike: "3840×2160", drawnAt: "3840×2160",
                      recordsAt: "1920×1080", gigabytesPerHour: "1.1"),
            ],
            audio: [
                .init(name: "MacBook Pro Microphone (default)", channels: "1", isRecorded: true, gigabytesPerHour: "0.1"),
                .init(name: "RØDE Wireless GO II RX", channels: "2", isRecorded: false, gigabytesPerHour: "not recorded"),
                .init(name: "System audio", channels: "stereo", isRecorded: true, gigabytesPerHour: "0.1"),
            ],
            total: "Total 2.2 GB/h. 2 hours need 4.3 GB, 3.1 GB free.",
            outputFolder: "Files go to ~/Movies/Multi Screen Recorder",
            continuity: "Recording continues when displays or audio sources change."))
    }

    @Test func theColumns() {
        #expect(WhatWillBeRecorded.displayColumns == ["Display", "Looks like", "Drawn at", "Records at", "GB/h"])
        #expect(WhatWillBeRecorded.audioColumns == ["Audio", "Channels", "GB/h"])
    }

    /// The tables and the total line in docs/design/recorder.md, as Markdown.
    @Test func theDesignShowsTheExample() throws {
        let example = section()
        var lines = ["| " + WhatWillBeRecorded.displayColumns.joined(separator: " | ") + " |",
                     "|" + String(repeating: "---|", count: WhatWillBeRecorded.displayColumns.count)]
        lines += example.displays.map {
            "| \($0.number) \($0.name) | \($0.looksLike) | \($0.drawnAt) | \($0.recordsAt) | \($0.gigabytesPerHour) |"
        }
        lines += ["", "| " + WhatWillBeRecorded.audioColumns.joined(separator: " | ") + " |",
                  "|" + String(repeating: "---|", count: WhatWillBeRecorded.audioColumns.count)]
        lines += example.audio.map { "| \($0.name) | \($0.channels) | \($0.gigabytesPerHour) |" }
        lines += ["", try #require(example.total)]
        #expect(try repositoryFile("docs/design/recorder.md").contains(lines.joined(separator: "\n") + "\n"))
    }

    @Test func recordsAtFollowsTheResolution() {
        #expect(section { $0.resolution = .native }.displays.map(\.recordsAt) == ["3456×2234", "3840×2160"])
    }

    @Test func audioModeNoneRecordsNoInputAndNoMicrophonesGuideTrack() {
        let none = section { $0.audioMode = .none }
        #expect(none.audio.dropLast().allSatisfy { !$0.isRecorded && $0.gigabytesPerHour == "not recorded" })
        #expect(none.audio.last?.isRecorded == true)
        #expect(none.displays.map(\.gigabytesPerHour) == ["0.9", "1.0"])
    }

    @Test func noInputIsRecordedWithoutADefault() {
        let inputs = DesignExample.audioInputs.map {
            AudioInputInfo(name: $0.name, channelCount: $0.channelCount, isDefault: false)
        }
        let audio = section(audioInputs: inputs).audio
        #expect(audio.map(\.name) == ["MacBook Pro Microphone", "RØDE Wireless GO II RX", "System audio"])
        #expect(audio.dropLast().allSatisfy { !$0.isRecorded })
    }

    @Test func systemAudioOffIsNotRecorded() {
        #expect(section { $0.systemAudio = false }.audio.last
            == .init(name: "System audio", channels: "stereo", isRecorded: false, gigabytesPerHour: "not recorded"))
    }

    @Test(arguments: [nil, OutputFolderProbe.unusable("gone"), .usable(.unreadable("no such volume"))])
    func withoutTheFreeSpaceTheTotalLeavesItOut(outputFolder: OutputFolderProbe?) {
        #expect(section(outputFolder: outputFolder).total == "Total 2.2 GB/h. 2 hours need 4.3 GB.")
    }

    @Test func oneHourNeedsItsShare() {
        #expect(section { $0.requiredRecordingHours = 1 }.total == "Total 2.2 GB/h. 1 hour needs 2.2 GB, 3.1 GB free.")
    }

    @Test func theOutputFolderIsAsSet() {
        #expect(section { $0.outputFolder = "/Volumes/Data/Recordings" }.outputFolder
            == "Files go to /Volumes/Data/Recordings")
    }

    @Test func unreadableDisplaysShowTheErrorInPlaceOfTheirTableAndNoTotal() {
        let broken = section(displays: .failure(DeviceReadError("the display X does not report its display mode")))
        #expect(broken.displaysError == "The displays cannot be read: the display X does not report its display mode")
        #expect(broken.displays.isEmpty)
        #expect(broken.audio == section().audio)
        #expect(broken.total == nil)
    }

    private static func unreadable(isDefault: Bool) -> AudioInputInfo {
        AudioInputInfo(name: "X", channelCount: .failure(DeviceReadError("no format")), isDefault: isDefault)
    }

    @Test func anUnreadableInputThatIsNotRecordedIsARowAndKeepsTheTotal() {
        let withUnreadable = section(audioInputs: DesignExample.audioInputs + [Self.unreadable(isDefault: false)])
        #expect(withUnreadable.audio[2]
            == .init(name: "X", channels: "cannot be read", isRecorded: false, gigabytesPerHour: "not recorded"))
        #expect(withUnreadable.displays == section().displays)
        #expect(withUnreadable.total == section().total)
    }

    @Test func anUnreadableRecordedInputLeavesTheTotalOut() {
        let broken = section(audioInputs: [Self.unreadable(isDefault: true)])
        #expect(broken.audio.first
            == .init(name: "X (default)", channels: "cannot be read", isRecorded: true, gigabytesPerHour: "unknown"))
        #expect(broken.displays == section().displays)
        #expect(broken.total == nil)
    }
}
