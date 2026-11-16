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
                .init(name: "MacBook Pro Microphone (default)", channels: "1 channel", isRecorded: true, gigabytesPerHour: "0.1"),
                .init(name: "RØDE Wireless GO II RX", channels: "2 channels", isRecorded: true, gigabytesPerHour: "0.1"),
                .init(name: "System audio", channels: "stereo", isRecorded: true, gigabytesPerHour: "0.1"),
            ],
            total: .init(gigabytesPerHour: "5.3", need: "2 hours need 10.7 GB, 3.1 GB free."),
            outputFolder: "Files go to ~/Movies/Multi Screen Recorder",
            continuity: "Recording continues when displays or audio sources change."))
    }

    @Test func the1080pSettingsOfBeforeAutoModeRecordSmallerFiles() {
        #expect(section().displays.map(\.recordsAt) == ["1670×1080", "1920×1080"])
        #expect(section().total == .init(gigabytesPerHour: "2.2", need: "2 hours need 4.3 GB, 3.1 GB free."))
    }

    @Test func theColumns() {
        #expect(WhatWillBeRecorded.columns == ["Source", "Looks like", "Drawn at", "Records at", "GB/h max"])
    }

    /// The table with its total row, and the line of what the required
    /// recording hours need, in docs/design/recorder.md, as Markdown.
    @Test func theDesignShowsTheExample() throws {
        let example = defaultSection
        var lines = ["| " + WhatWillBeRecorded.columns.joined(separator: " | ") + " |",
                     "|" + String(repeating: "---|", count: WhatWillBeRecorded.columns.count)]
        let rows = example.displayRows + example.audioRows + [try #require(example.totalRow)]
        lines += rows.map { "| " + $0.cells.joined(separator: " | ") + " |" }
        lines += ["", try #require(example.total?.need)]
        #expect(try repositoryFile("docs/design/recorder.md").contains(lines.joined(separator: "\n") + "\n"))
    }

    /// The total is the table's last row, in the GB/h max column.
    @Test func theTotalIsARowWithItsValueInTheLastColumn() {
        #expect(defaultSection.totalRow == .init(cells: ["Total", "", "", "", "5.3"], isRecorded: true))
        #expect(section(displays: .failure(DeviceReadError("no display"))).totalRow == nil)
    }

    @Test func oneTableHasTheDisplayRowsThenTheAudioRowsAndSystemAudioLast() {
        let example = defaultSection
        #expect(example.displayRows == [
            .init(cells: ["1 Built-in Retina Display", "1728×1117", "3456×2234", "1728×1116", "1.0"], isRecorded: true),
            .init(cells: ["2 LG HDR 4K", "3840×2160", "3840×2160", "3840×2160", "4.1"], isRecorded: true),
        ])
        #expect(example.audioRows == [
            .init(cells: ["MacBook Pro Microphone (default)", "", "", "1 channel", "0.1"], isRecorded: true),
            .init(cells: ["RØDE Wireless GO II RX", "", "", "2 channels", "0.1"], isRecorded: true),
            .init(cells: ["System audio", "", "", "stereo", "0.1"], isRecorded: true),
        ])
    }

    @Test func aSourceNotRecordedIsARowWithNotRecordedAndIsDimmed() {
        let rows = section(audioInputs: DesignExample.audioInputs + [AudioInputInfo(
            name: "AirPods", channelCount: 1, isDefault: false, transport: .bluetooth)]).audioRows
        #expect(rows.last { $0.cells[0] == "AirPods" } == .init(cells: ["AirPods", "", "", "1 channel", "0"], isRecorded: false))
    }

    @Test func anUnreadableRecordedInputIsARowWithUnknown() {
        let rows = section(audioInputs: [Self.unreadable(isDefault: true)]).audioRows
        #expect(rows.first == .init(cells: ["X (default)", "", "", "cannot be read", "?"], isRecorded: true))
    }

    @Test func everyRowHasOneCellPerColumn() {
        let example = section(audioInputs: DesignExample.audioInputs + [Self.unreadable(isDefault: false)])
        for row in example.displayRows + example.audioRows { #expect(row.cells.count == WhatWillBeRecorded.columns.count) }
    }

    @Test func recordsAtFollowsTheResolution() {
        #expect(section { $0.resolution = .native }.displays.map(\.recordsAt) == ["1728×1116", "3840×2160"])
        #expect(section { $0.resolution = .p720 }.displays.map(\.recordsAt) == ["1112×720", "1280×720"])
    }

    @Test func audioModeNoneRecordsNoInputAndNoMicrophonesGuideTrack() {
        let none = section { $0.audioMode = .none }
        #expect(none.audio.dropLast().allSatisfy { !$0.isRecorded && $0.gigabytesPerHour == "0" })
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
        #expect(audio[2].gigabytesPerHour == "0")
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

    @Test func theTextForMSRCheckIsOneTableAndTheTotal() {
        #expect(defaultSection.text == """
            What will be recorded
              Source                            Looks like  Drawn at   Records at  GB/h max
              1 Built-in Retina Display         1728×1117   3456×2234  1728×1116        1.0
              2 LG HDR 4K                       3840×2160   3840×2160  3840×2160        4.1
              ─────────────────────────────────────────────────────────────────────────────
              MacBook Pro Microphone (default)                         1 channel        0.1
              RØDE Wireless GO II RX                                   2 channels       0.1
              System audio                                             stereo           0.1
              ─────────────────────────────────────────────────────────────────────────────
              Total                                                                     5.3
              2 hours need 10.7 GB, 3.1 GB free.
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
        #expect(broken.text.contains("System audio"))
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
            == .init(name: "System audio", channels: "stereo", isRecorded: false, gigabytesPerHour: "0"))
    }

    @Test(arguments: [nil, OutputFolderProbe.unusable("gone"), .usable(.unreadable("no such volume"))])
    func withoutTheFreeSpaceTheTotalLeavesItOut(outputFolder: OutputFolderProbe?) {
        #expect(section(outputFolder: outputFolder).total == .init(gigabytesPerHour: "2.2", need: "2 hours need 4.3 GB."))
    }

    @Test func oneHourNeedsItsShare() {
        #expect(section { $0.requiredRecordingHours = 1 }.total?.need == "1 hour needs 2.2 GB, 3.1 GB free.")
    }

    @Test func aHugeRequiredRecordingTimeIsNamedWithoutCrashing() {
        #expect(section { $0.requiredRecordingHours = 1e20 }.total?.need.contains("1e+20 hours") == true)
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
            == .init(name: "X", channels: "cannot be read", isRecorded: false, gigabytesPerHour: "0"))
        #expect(withUnreadable.displays == section().displays)
        #expect(withUnreadable.total == section().total)
    }

    @Test func anUnreadableRecordedInputLeavesTheTotalOut() {
        let broken = section(audioInputs: [Self.unreadable(isDefault: true)])
        #expect(broken.audio.first
            == .init(name: "X (default)", channels: "cannot be read", isRecorded: true, gigabytesPerHour: "?"))
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
