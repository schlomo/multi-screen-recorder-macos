import Testing
@testable import RecorderLogic

@Suite struct WhatWillBeRecordedTests {
    private static let designFolder = OutputFolderProbe.usable(.bytes(3_100_000_000))

    private func section(
        _ edit: (inout Settings) -> Void = { _ in },
        displays: Result<[DisplayInfo], DeviceReadError> = .success(DesignExample.displays),
        audioInputs: [AudioInputInfo] = DesignExample.audioInputs,
        audioInputsError: DeviceReadError? = nil,
        outputFolder: OutputFolderProbe? = designFolder
    ) -> WhatWillBeRecorded {
        var settings = Settings.manual
        edit(&settings)
        return WhatWillBeRecorded(settings: settings, displays: displays,
            audioInputs: audioInputsError.map { .failure($0) } ?? .success(audioInputs), outputFolder: outputFolder)
    }

    /// Auto mode, the default: Native and Wired.
    private var defaultSection: WhatWillBeRecorded {
        WhatWillBeRecorded(
            settings: .defaults, displays: .success(DesignExample.displays),
            audioInputs: .success(DesignExample.audioInputs), outputFolder: Self.designFolder)
    }

    @Test func theDefaultsWithTheDesignsDevices() {
        #expect(defaultSection == WhatWillBeRecorded(
            displaysError: nil,
            displays: [
                .init(number: 1, name: "Built-in Retina Display", looksLike: "1728×1117", drawnAt: "3456×2234",
                      recordsAt: "1728×1116", gigabytesPerHour: "1.0"),
                .init(number: 2, name: "LG HDR 4K", looksLike: "3840×2160", drawnAt: "3840×2160",
                      recordsAt: "3840×2160", gigabytesPerHour: "4.1"),
            ],
            audioError: nil,
            audio: [
                .init(name: "MacBook Pro Microphone (default)", channels: "1", isRecorded: true, gigabytesPerHour: "0.1"),
                .init(name: "RØDE Wireless GO II RX", channels: "2", isRecorded: true, gigabytesPerHour: "0.1"),
                .init(name: "System audio", channels: "stereo", isRecorded: true, gigabytesPerHour: "0.1"),
            ],
            total: "Total 5.3 GB/h. 2 hours need 10.7 GB, 3.1 GB free.",
            outputFolder: "Files go to ~/Movies/Multi Screen Recorder",
            continuity: "Recording continues when displays or audio sources change."))
    }

    @Test func the1080pSettingsOfBeforeAutoModeRecordSmallerFiles() {
        #expect(section().displays.map(\.recordsAt) == ["1670×1080", "1920×1080"])
        #expect(section().total == "Total 2.2 GB/h. 2 hours need 4.3 GB, 3.1 GB free.")
    }

    @Test func theColumns() {
        #expect(WhatWillBeRecorded.displayColumns == ["Display", "Looks like", "Drawn at", "Records at", "GB/h"])
        #expect(WhatWillBeRecorded.audioColumns == ["Audio", "Channels", "GB/h"])
    }

    /// The tables and the total line in docs/design/recorder.md, as Markdown.
    @Test func theDesignShowsTheExample() throws {
        let example = defaultSection
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
        #expect(section { $0.resolution = .native }.displays.map(\.recordsAt) == ["1728×1116", "3840×2160"])
        #expect(section { $0.resolution = .p720 }.displays.map(\.recordsAt) == ["1112×720", "1280×720"])
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

    @Test func autoModeIgnoresTheSlidersAndRecordsNativeAndWired() {
        let auto = section { $0.auto = true; $0.resolution = .p720; $0.audioMode = .none }
        #expect(auto.displays == defaultSection.displays)
        #expect(auto.audio == defaultSection.audio)
    }

    private static let airPods = AudioInputInfo(name: "AirPods", channelCount: 1, isDefault: false, transport: .bluetooth)
    private static let virtualInput = AudioInputInfo(name: "Loopback", channelCount: 2, isDefault: false, transport: .virtual)

    @Test func wiredRecordsTheDefaultAndWiredInputsButNotBluetoothOrVirtualOnes() {
        let audio = section({ $0.audioMode = .wired },
                            audioInputs: DesignExample.audioInputs + [Self.airPods, Self.virtualInput]).audio
        #expect(audio.map(\.isRecorded) == [true, true, false, false, true])
        #expect(audio[2].gigabytesPerHour == "not recorded")
    }

    @Test func allRecordsEveryInput() {
        let audio = section({ $0.audioMode = .allInputs },
                            audioInputs: DesignExample.audioInputs + [Self.airPods, Self.virtualInput]).audio
        #expect(audio.map(\.isRecorded) == [true, true, true, true, true])
    }

    @Test func aBluetoothDefaultMicrophoneIsRecordedInEveryModeButNone() {
        let headset = AudioInputInfo(name: "AirPods", channelCount: 1, isDefault: true, transport: .bluetooth)
        for mode in AudioMode.allCases {
            let audio = section({ $0.audioMode = mode }, audioInputs: [headset]).audio
            #expect(audio.first?.isRecorded == (mode != .none))
        }
    }

    @Test func theTextForMSRCheckHasTheTablesAndTheTotal() {
        #expect(defaultSection.text == """
            What will be recorded
              Display                    Looks like  Drawn at   Records at  GB/h
              1 Built-in Retina Display  1728×1117   3456×2234  1728×1116   1.0
              2 LG HDR 4K                3840×2160   3840×2160  3840×2160   4.1
              Audio                             Channels  GB/h
              MacBook Pro Microphone (default)  1         0.1
              RØDE Wireless GO II RX            2         0.1
              System audio                      stereo    0.1
              Total 5.3 GB/h. 2 hours need 10.7 GB, 3.1 GB free.
              Files go to ~/Movies/Multi Screen Recorder

            """)
    }

    @Test func theDesignShowsTheTextOfMSRCheck() throws {
        #expect(try repositoryFile("docs/design/recorder.md").contains("```\n\(defaultSection.text)```\n"))
    }

    @Test func theTextShowsErrorsInPlaceOfTheirTables() {
        let broken = section(displays: .failure(DeviceReadError("no display")), audioInputsError: DeviceReadError("no list"))
        #expect(broken.text.contains("  The displays cannot be read: no display\n"))
        #expect(broken.text.contains("  The audio inputs cannot be read: no list\n"))
        #expect(!broken.text.contains("Total"))
    }

    @Test func theTextIsMadeFromTheSameDataAsTheWindow() {
        let facts = ReadyCheckFacts(
            screenRecording: .granted, microphoneGranted: true, displays: .success(DesignExample.displays),
            audioInputs: .success(DesignExample.audioInputs), outputFolder: Self.designFolder)
        #expect(WhatWillBeRecorded(settings: .defaults, facts: facts) == defaultSection)
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

    @Test func aHugeRequiredRecordingTimeIsNamedWithoutCrashing() {
        #expect(section { $0.requiredRecordingHours = 1e20 }.total?.contains("1e+20 hours") == true)
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

    @Test func anUnreadableListOfAudioInputsIsSaidAndLeavesTheTotalOut() {
        let broken = section(audioInputsError: DeviceReadError("no list"))
        #expect(broken.audioError == "The audio inputs cannot be read: no list")
        #expect(broken.audio.map(\.name) == ["System audio"])
        #expect(broken.displays == section().displays)
        #expect(broken.total == nil)
    }

    @Test func audioModeNoneKeepsTheTotalWithoutTheListOfAudioInputs() {
        let broken = section({ $0.audioMode = .none }, audioInputsError: DeviceReadError("no list"))
        #expect(broken.audioError == "The audio inputs cannot be read: no list")
        #expect(broken.total == section({ $0.audioMode = .none }).total)
    }
}
