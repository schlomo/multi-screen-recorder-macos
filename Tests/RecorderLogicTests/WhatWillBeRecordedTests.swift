import Testing
@testable import RecorderLogic

@Suite struct WhatWillBeRecordedTests {
    private static let designFolder = OutputFolderProbe.usable(.bytes(3_100_000_000))

    private func section(
        _ edit: (inout Settings) -> Void = { _ in },
        screens: Result<[ScreenInfo], DeviceReadError> = .success(DesignExample.screens),
        audioInputs: [AudioInputInfo] = DesignExample.audioInputs,
        audioInputsError: DeviceReadError? = nil,
        outputFolder: OutputFolderProbe? = designFolder
    ) -> WhatWillBeRecorded {
        var settings = Settings.manual
        edit(&settings)
        return WhatWillBeRecorded(settings: settings, screens: screens,
            audioInputs: audioInputsError.map { .failure($0) } ?? .success(audioInputs), outputFolder: outputFolder)
    }

    /// Auto mode, the default: Native and Wired.
    private var defaultSection: WhatWillBeRecorded {
        WhatWillBeRecorded(
            settings: .defaults, screens: .success(DesignExample.screens),
            audioInputs: .success(DesignExample.audioInputs), outputFolder: Self.designFolder)
    }

    @Test func theDefaultsWithTheDesignsDevices() {
        #expect(defaultSection == WhatWillBeRecorded(
            settingsLine: "Settings: Auto (resolution Native, audio mode Wired), system audio on",
            screensError: nil,
            screens: [
                .init(number: 1, name: "Built-in Retina Display", looksLike: "1728×1117", drawnAt: "3456×2234",
                      recordsAt: "1728×1116", gigabytesPerHour: "1.0"),
                .init(number: 2, name: "LG HDR 4K", looksLike: "3840×2160", drawnAt: "3840×2160",
                      recordsAt: "3840×2160", gigabytesPerHour: "4.1"),
            ],
            audioError: nil,
            audio: [
                .init(source: .systemAudio(isRecorded: true), channels: "stereo", isRecorded: true, gigabytesPerHour: "0.1"),
                .init(source: .audioInput(1, name: "MacBook Pro Microphone (default)"), channels: "1 channel", isRecorded: true,
                      gigabytesPerHour: "0.1"),
                .init(source: .audioInput(2, name: "RØDE Wireless GO II RX"), channels: "2 channels", isRecorded: true,
                      gigabytesPerHour: "0.1"),
            ],
            total: .init(gigabytesPerHour: "5.3", need: "2 hours need 10.7 GB, 3.1 GB free."),
            outputFolder: "Files go to ~/Movies/Multi Screen Recorder",
            continuity: "Recording continues when screens or audio sources change."))
    }

    @Test func the1080pSettingsOfBeforeAutoModeRecordSmallerFiles() {
        #expect(section().screens.map(\.recordsAt) == ["1670×1080", "1920×1080"])
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
        let rows = example.screenRows + example.audioRows + [try #require(example.totalRow)]
        lines += rows.map { "| " + $0.cells.joined(separator: " | ") + " |" }
        lines += ["", try #require(example.total?.need)]
        #expect(try repositoryFile("docs/design/recorder.md").contains(lines.joined(separator: "\n") + "\n"))
    }

    /// The total is the table's last row, in the GB/h max column.
    @Test func theTotalIsARowWithItsValueInTheLastColumn() {
        #expect(defaultSection.totalRow == .init(source: nil, values: ["", "", "", "5.3"], isRecorded: true))
        #expect(defaultSection.totalRow?.cells == ["Total", "", "", "", "5.3"])
        #expect(section(screens: .failure(DeviceReadError("no screen"))).totalRow == nil)
    }

    /// The screens by number, then the audio sources by number, the system audio (0) first.
    @Test func oneTableHasTheScreenRowsThenTheAudioRowsAndSystemAudioFirst() {
        let example = defaultSection
        #expect(example.screenRows.map(\.cells) == [
            ["Screen 1 - Built-in Retina Display", "1728×1117", "3456×2234", "1728×1116", "1.0"],
            ["Screen 2 - LG HDR 4K", "3840×2160", "3840×2160", "3840×2160", "4.1"],
        ])
        #expect(example.audioRows.map(\.cells) == [
            ["Audio 0 - System", "", "", "stereo", "0.1"],
            ["Audio 1 - MacBook Pro Microphone (default)", "", "", "1 channel", "0.1"],
            ["Audio 2 - RØDE Wireless GO II RX", "", "", "2 channels", "0.1"],
        ])
        #expect((example.screenRows + example.audioRows).map(\.source?.kind)
            == [.screen, .screen, .systemAudio, .audioInput, .audioInput])
    }

    @Test func aSourceNotRecordedIsARowWithNotRecordedAndIsDimmed() {
        let rows = section({ $0.audioMode = .wired }, audioInputs: DesignExample.audioInputs + [AudioInputInfo(
            name: "AirPods", channelCount: 1, isDefault: false, transport: .bluetooth, uid: "A")]).audioRows
        #expect(rows.last { $0.cells[0] == "AirPods (Bluetooth)" }
            == .init(source: .audioInput(nil, name: "AirPods (Bluetooth)"), values: ["", "", "1 channel", "-"], isRecorded: false))
    }

    @Test func anUnreadableRecordedInputIsARowWithUnknown() {
        let rows = section(audioInputs: [Self.unreadable(isDefault: true)]).audioRows
        #expect(rows[1].cells == ["Audio 1 - X (default)", "", "", "cannot be read", "?"])
    }

    @Test func everyRowHasOneCellPerColumn() {
        let example = section(audioInputs: DesignExample.audioInputs + [Self.unreadable(isDefault: false)])
        for row in example.screenRows + example.audioRows { #expect(row.cells.count == WhatWillBeRecorded.columns.count) }
    }

    @Test func recordsAtFollowsTheResolution() {
        #expect(section { $0.resolution = .native }.screens.map(\.recordsAt) == ["1728×1116", "3840×2160"])
        #expect(section { $0.resolution = .p720 }.screens.map(\.recordsAt) == ["1112×720", "1280×720"])
    }

    /// D55: recorded inputs are numbered from 1 in the order listed, as
    /// the recording numbers them at its start; one not recorded gets no
    /// number, the system audio is 0.
    @Test func recordedInputsAreNumberedInOrderAndOnesNotRecordedGetNoNumber() {
        let audio = section({ $0.audioMode = .wired },
                            audioInputs: [Self.airPods] + DesignExample.audioInputs + [Self.virtualInput]).audio
        #expect(audio.map(\.source.number) == [0, 1, 2, nil, nil])
        #expect(audio.map(\.source.text) == [
            "Audio 0 - System", "Audio 1 - MacBook Pro Microphone (default)", "Audio 2 - RØDE Wireless GO II RX",
            "AirPods (Bluetooth)", "Loopback (virtual)",
        ])
    }

    /// D55: the window numbers only what the recording records; it opens
    /// an input by its Core Audio UID, so one without is not recorded.
    @Test func anInputWithoutAUIDIsNotRecordedAndGetsNoNumber() {
        let noUID = AudioInputInfo(name: "Mystery", channelCount: 1, isDefault: false, transport: .usb)
        let withNoUID = section({ $0.audioMode = .wired }, audioInputs: [noUID] + DesignExample.audioInputs)
        #expect(withNoUID.audio[3] == .init(source: .audioInput(nil, name: "Mystery (no device ID)"), channels: "1 channel",
                                            isRecorded: false, gigabytesPerHour: "-"))
        #expect(withNoUID.audio.map(\.source.number) == [0, 1, 2, nil])
        #expect(withNoUID.total == section { $0.audioMode = .wired }.total)
    }

    /// D55: the window's numbers are the recording's, also when an input has no UID.
    @Test func theWindowNumbersTheInputsAsTheRecordingDoes() {
        var settings = Settings.manual
        settings.audioMode = .allInputs
        let inputs = [
            AudioInputInfo(name: "A", channelCount: 1, isDefault: false, transport: .usb, uid: "A"),
            AudioInputInfo(name: "No UID", channelCount: 1, isDefault: true, transport: .usb),
            AudioInputInfo(name: "B", channelCount: 2, isDefault: false, transport: .bluetooth, uid: "B"),
        ]
        let window = WhatWillBeRecorded(settings: settings, screens: .success(DesignExample.screens),
                                        audioInputs: .success(inputs), outputFolder: nil)
        var tracker = AudioTracker(settings: settings)
        let started = tracker.begin(inputs: inputs, mainDisplayID: 1, screens: [1], at: 0).actions.compactMap { action -> String? in
            if case .startInput(_, let number, let name) = action { "\(number) \(name)" } else { nil }
        }
        let numbered = window.audio.compactMap { audio in audio.source.number.flatMap { $0 > 0 ? "\($0) \(audio.name)" : nil } }
        #expect(started == ["1 A", "2 B"])
        #expect(numbered == started)
    }

    @Test func audioModeNoneRecordsNoInputAndNoAudioInputsGuideTrack() {
        let none = section { $0.audioMode = .none }
        #expect(none.audio.dropFirst().allSatisfy { !$0.isRecorded && $0.gigabytesPerHour == "-" })
        #expect(none.audio.first?.isRecorded == true)
        #expect(none.screens.map(\.gigabytesPerHour) == ["0.9", "1.0"])
    }

    @Test func noInputIsRecordedWithoutADefault() {
        let inputs = DesignExample.audioInputs.map {
            AudioInputInfo(name: $0.name, channelCount: $0.channelCount, isDefault: false)
        }
        let audio = section(audioInputs: inputs).audio
        #expect(audio.map(\.source.text) == ["Audio 0 - System", "MacBook Pro Microphone", "RØDE Wireless GO II RX"])
        #expect(audio.dropFirst().allSatisfy { !$0.isRecorded })
    }

    @Test func autoModeIgnoresTheSlidersAndRecordsNativeAndWired() {
        let auto = section { $0.auto = true; $0.resolution = .p720; $0.audioMode = .none }
        #expect(auto.screens == defaultSection.screens)
        #expect(auto.audio == defaultSection.audio)
    }

    private static let airPods = AudioInputInfo(name: "AirPods", channelCount: 1, isDefault: false, transport: .bluetooth, uid: "AirPods")
    private static let virtualInput = AudioInputInfo(name: "Loopback", channelCount: 2, isDefault: false, transport: .virtual, uid: "Loopback")

    @Test func wiredRecordsTheDefaultAndWiredInputsButNotBluetoothOrVirtualOnes() {
        let audio = section({ $0.audioMode = .wired },
                            audioInputs: DesignExample.audioInputs + [Self.airPods, Self.virtualInput]).audio
        #expect(audio.map(\.isRecorded) == [true, true, true, false, false])
        #expect(audio[3].gigabytesPerHour == "-")
    }

    @Test func allRecordsEveryInput() {
        let audio = section({ $0.audioMode = .allInputs },
                            audioInputs: DesignExample.audioInputs + [Self.airPods, Self.virtualInput]).audio
        #expect(audio.map(\.isRecorded) == [true, true, true, true, true])
    }

    @Test func aBluetoothDefaultMicrophoneIsRecordedInEveryModeButNone() {
        let headset = AudioInputInfo(name: "AirPods", channelCount: 1, isDefault: true, transport: .bluetooth, uid: "AirPods")
        for mode in AudioMode.allCases {
            let audio = section({ $0.audioMode = mode }, audioInputs: [headset]).audio
            #expect(audio[1].isRecorded == (mode != .none))
        }
    }

    @Test func theTextForMSRCheckIsOneTableAndTheTotal() {
        #expect(defaultSection.text == """
            What will be recorded
              Settings: Auto (resolution Native, audio mode Wired), system audio on
              Source                                      Looks like  Drawn at   Records at  GB/h max
              ───────────────────────────────────────────────────────────────────────────────────────
              Screen 1 - Built-in Retina Display          1728×1117   3456×2234  1728×1116        1.0
              Screen 2 - LG HDR 4K                        3840×2160   3840×2160  3840×2160        4.1
              ───────────────────────────────────────────────────────────────────────────────────────
              Audio 0 - System                                                   stereo           0.1
              Audio 1 - MacBook Pro Microphone (default)                         1 channel        0.1
              Audio 2 - RØDE Wireless GO II RX                                   2 channels       0.1
              ───────────────────────────────────────────────────────────────────────────────────────
              Total                                                                               5.3
              2 hours need 10.7 GB, 3.1 GB free.
              Files go to ~/Movies/Multi Screen Recorder

            """)
    }

    @Test func theDesignShowsTheTextOfMSRCheck() throws {
        #expect(try repositoryFile("docs/design/recorder.md").contains("```\n\(defaultSection.text)```\n"))
    }

    // The settings line, and why an input is not recorded.

    // Why an input is not recorded, after its name in parentheses: the reason comes from the rule that does not record it.

    private func reason(_ transport: AudioTransport, isDefault: Bool = false, uid: String? = "U", mode: AudioMode) -> String? {
        var settings = Settings.manual
        settings.audioMode = mode
        return settings.reasonNotRecorded(AudioInputInfo(name: "X", channelCount: 1, isDefault: isDefault, transport: transport, uid: uid))
    }

    @Test(arguments: [(AudioTransport.virtual, "virtual"), (.bluetooth, "Bluetooth"), (.bluetoothLE, "Bluetooth"),
                      (.aggregate, "aggregate"), (.airPlay, "AirPlay"), (.continuityCapture, "Continuity Capture"),
                      (.unknown, "unknown connection"), (.unreadable, "unknown connection")])
    func underWiredAnInputThatIsNotWiredSaysItsConnection(transport: AudioTransport, expected: String) {
        #expect(reason(transport, mode: .wired) == expected)
        #expect(reason(transport, isDefault: true, mode: .wired) == nil)
        #expect(reason(transport, mode: .allInputs) == nil)
    }

    @Test(arguments: AudioTransport.allCases.filter(\.isWired))
    func underWiredAWiredInputIsRecordedAndNeedsNoReason(transport: AudioTransport) {
        #expect(reason(transport, mode: .wired) == nil)
    }

    @Test(arguments: AudioMode.allCases)
    func anInputWithoutADeviceIDSaysSoWhereTheModeWantsIt(mode: AudioMode) {
        let wanted = reason(.usb, isDefault: true, uid: nil, mode: mode)
        #expect(wanted == (mode == .none ? nil : "no device ID"))
        #expect(reason(.usb, uid: nil, mode: .allInputs) == "no device ID")
        #expect(reason(.usb, uid: nil, mode: .wired) == "no device ID")
        #expect(reason(.virtual, uid: nil, mode: .wired) == "virtual")
    }

    @Test(arguments: AudioTransport.allCases)
    func underNoneAndDefaultMicrophoneTheSettingsLineGivesTheReasonNotTheName(transport: AudioTransport) {
        #expect(reason(transport, mode: .none) == nil)
        #expect(reason(transport, mode: .defaultMicrophone) == nil)
    }

    /// Auto mode records Wired whatever the stored audio mode says, and so does the reason.
    @Test func autoModeGivesTheReasonsOfWiredWhateverTheStoredAudioModeIs() {
        var settings = Settings.defaults
        settings.auto = true
        settings.audioMode = .allInputs
        func input(_ transport: AudioTransport) -> AudioInputInfo {
            AudioInputInfo(name: "X", channelCount: 1, isDefault: false, transport: transport, uid: "U")
        }
        #expect(settings.reasonNotRecorded(input(.virtual)) == "virtual")
        #expect(settings.reasonNotRecorded(input(.bluetooth)) == "Bluetooth")
        #expect(settings.reasonNotRecorded(input(.usb)) == nil)
    }

    @Test func theNumberDigitsAreThoseOfTheHighestAudioNumber() {
        #expect(defaultSection.numberDigits == 1)
        let ten = (1...10).map { AudioInputInfo(name: "M\($0)", channelCount: 1, isDefault: $0 == 1, transport: .usb, uid: "U\($0)") }
        var settings = Settings.defaults
        settings.auto = false
        settings.audioMode = .allInputs
        let many = WhatWillBeRecorded(settings: settings, screens: .success([]), audioInputs: .success(ten), outputFolder: nil)
        #expect(many.numberDigits == 2)
        #expect(WhatWillBeRecorded(settings: settings, screens: .success([]), audioInputs: .success([]), outputFolder: nil).numberDigits == 1)
    }

    /// The blank where the number would be is as wide as the widest number's, so the names line up.
    @Test func theNamesLineUpWithTwoDigitNumbers() {
        var settings = Settings.defaults
        settings.auto = false
        settings.audioMode = .allInputs
        let inputs = (1...10).map { AudioInputInfo(name: "Mic\($0)", channelCount: 1, isDefault: $0 == 1, transport: .usb, uid: "U\($0)") }
            + [AudioInputInfo(name: "Mystery", channelCount: 1, isDefault: false, transport: .usb)]
        let lines = WhatWillBeRecorded(settings: settings, screens: .success([]), audioInputs: .success(inputs), outputFolder: nil)
            .text.split(separator: "\n")
        let numbered = lines.first { $0.contains("Audio 10 - Mic10") }
        let notRecorded = lines.first { $0.contains("Mystery") }
        #expect(numbered?.ranges(of: "Mic10").first?.lowerBound.utf16Offset(in: numbered ?? "")
            == notRecorded?.ranges(of: "Mystery").first?.lowerBound.utf16Offset(in: notRecorded ?? ""))
        #expect(numbered != nil && notRecorded != nil)
    }

    @Test func theReasonFollowsTheNameInTheTable() {
        let rows = section({ $0.audioMode = .wired }, audioInputs: [Self.virtualInput, Self.airPods,
            AudioInputInfo(name: "Mystery", channelCount: 1, isDefault: false, transport: .usb)]).audioRows
        #expect(rows.compactMap { $0.source?.name }.suffix(3) == ["Loopback (virtual)", "AirPods (Bluetooth)", "Mystery (no device ID)"])
        let withoutAudio = section({ $0.audioMode = .none }, audioInputs: [Self.virtualInput]).audioRows
        let names = withoutAudio.compactMap { $0.source?.name }
        #expect(names.contains("Loopback"))
    }

    /// The numbered rows read 0, 1, 2 … without a gap; inputs not recorded follow, in device order.
    @Test func inputsNotRecordedComeAfterTheNumberedRows() {
        let other = AudioInputInfo(name: "Zed", channelCount: 1, isDefault: false, transport: .virtual, uid: "Z")
        let shown = WhatWillBeRecorded(
            settings: .defaults, screens: .success(DesignExample.screens),
            audioInputs: .success([Self.virtualInput, Self.airPods] + DesignExample.audioInputs + [other]), outputFolder: nil)
        #expect(shown.audioRows.map { $0.source?.number } == [0, 1, 2, nil, nil, nil])
        #expect(shown.audioRows.suffix(3).compactMap { $0.source?.name } == ["Loopback (virtual)", "AirPods (Bluetooth)", "Zed (virtual)"])
    }

    @Test func theSettingsLineNamesTheEffectiveSettings() {
        #expect(defaultSection.settingsLine == "Settings: Auto (resolution Native, audio mode Wired), system audio on")
        #expect(section { $0.systemAudio = false; $0.audioMode = .allInputs }.settingsLine
            == "Settings: resolution 1080p, audio mode All, system audio off")
        #expect(section { $0.auto = true; $0.resolution = .p720; $0.audioMode = .none }.settingsLine
            == "Settings: Auto (resolution Native, audio mode Wired), system audio on")
    }

    @Test func underNoneOrDefaultMicrophoneTheSettingsLineGivesTheReason() {
        #expect(section { $0.audioMode = .none }.settingsLine
            == "Settings: resolution 1080p, audio mode None (no audio input is recorded), system audio on")
        #expect(section { $0.audioMode = .defaultMicrophone }.settingsLine
            == "Settings: resolution 1080p, audio mode Default microphone (only the default microphone is recorded), system audio on")
    }

    @Test func anInputNotRecordedKeepsItsNamesColumnAndSaysWhy() {
        var settings = Settings.defaults
        let blackHole = AudioInputInfo(name: "BlackHole 2ch", channelCount: 2, isDefault: false, transport: .virtual, uid: "BH")
        let section = WhatWillBeRecorded(
            settings: settings, screens: .success(DesignExample.screens),
            audioInputs: .success(DesignExample.audioInputs + [blackHole, Self.airPods]), outputFolder: nil)
        #expect(section.text.contains("\n            BlackHole 2ch (virtual)"))
        #expect(section.text.contains("\n            AirPods (Bluetooth)"))
        #expect(section.text.contains("  Audio 1 - MacBook Pro Microphone (default)"))
        #expect(section.audio.first { $0.name == "BlackHole 2ch (virtual)" }?.gigabytesPerHour == "-")
        settings.systemAudio = false
        #expect(WhatWillBeRecorded(settings: settings, screens: .success([]), audioInputs: .success([]), outputFolder: nil)
            .text.contains("\n            System audio"))
    }

    @Test func theTextShowsErrorsInPlaceOfTheirTables() {
        let broken = section(screens: .failure(DeviceReadError("no screen")), audioInputsError: DeviceReadError("no list"))
        #expect(broken.text.contains("  The screens cannot be read: no screen\n"))
        #expect(broken.text.contains("  The audio inputs cannot be read: no list\n"))
        #expect(broken.text.contains("Audio 0 - System"))
        #expect(!broken.text.contains("Total"))
    }

    @Test func theTextIsMadeFromTheSameDataAsTheWindow() {
        let facts = ReadyCheckFacts(
            screenRecording: .granted, microphoneGranted: true, screens: .success(DesignExample.screens),
            audioInputs: .success(DesignExample.audioInputs), outputFolder: Self.designFolder)
        #expect(WhatWillBeRecorded(settings: .defaults, facts: facts) == defaultSection)
    }

    @Test func systemAudioOffIsNotRecorded() {
        #expect(section { $0.systemAudio = false }.audio.last
            == .init(source: .systemAudio(isRecorded: false), channels: "stereo", isRecorded: false, gigabytesPerHour: "-"))
        #expect(section { $0.systemAudio = false }.audioRows.last?.cells[0] == "System audio")
    }

    /// With the system audio off its row goes with the others not recorded, at the end, aligned like them.
    @Test func theSystemAudioOffIsAfterTheRecordedRowsAndAlignedLikeTheOthersNotRecorded() {
        let off = section({ $0.audioMode = .wired; $0.systemAudio = false }, audioInputs: DesignExample.audioInputs + [Self.virtualInput])
        #expect(off.audioRows.map { $0.source?.number } == [1, 2, nil, nil])
        #expect(off.audioRows.compactMap { $0.source?.text }.suffix(2) == ["Loopback (virtual)", "System audio"])
        #expect(off.text.contains("\n            Loopback (virtual)"))
        #expect(off.text.contains("\n            System audio"))
        #expect(!off.text.contains("System audio ("))
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

    @Test func unreadableScreensShowTheErrorInPlaceOfTheirTableAndNoTotal() {
        let broken = section(screens: .failure(DeviceReadError("the screen X does not report its screen mode")))
        #expect(broken.screensError == "The screens cannot be read: the screen X does not report its screen mode")
        #expect(broken.screens.isEmpty)
        #expect(broken.audio == section().audio)
        #expect(broken.total == nil)
    }

    private static func unreadable(isDefault: Bool) -> AudioInputInfo {
        AudioInputInfo(name: "X", channelCount: .failure(DeviceReadError("no format")), isDefault: isDefault, uid: "X")
    }

    @Test func anUnreadableInputThatIsNotRecordedIsARowAndKeepsTheTotal() {
        let withUnreadable = section(audioInputs: DesignExample.audioInputs + [Self.unreadable(isDefault: false)])
        #expect(withUnreadable.audio[3]
            == .init(source: .audioInput(nil, name: "X"), channels: "cannot be read", isRecorded: false, gigabytesPerHour: "-",
                   readError: "no format"))
        #expect(withUnreadable.screens == section().screens)
        #expect(withUnreadable.total == section().total)
    }

    @Test func anUnreadableRecordedInputLeavesTheTotalOut() {
        let broken = section(audioInputs: [Self.unreadable(isDefault: true)])
        #expect(broken.audio[1]
            == .init(source: .audioInput(1, name: "X (default)"), channels: "cannot be read", isRecorded: true, gigabytesPerHour: "?",
                   readError: "no format"))
        #expect(broken.screens == section().screens)
        #expect(broken.total == nil)
    }

    @Test func anUnreadableListOfAudioInputsIsSaidAndLeavesTheTotalOut() {
        let broken = section(audioInputsError: DeviceReadError("no list"))
        #expect(broken.audioError == "The audio inputs cannot be read: no list")
        #expect(broken.audio.map(\.source.text) == ["Audio 0 - System"])
        #expect(broken.screens == section().screens)
        #expect(broken.total == nil)
    }

    @Test func audioModeNoneKeepsTheTotalWithoutTheListOfAudioInputs() {
        let broken = section({ $0.audioMode = .none }, audioInputsError: DeviceReadError("no list"))
        #expect(broken.audioError == "The audio inputs cannot be read: no list")
        #expect(broken.total == section({ $0.audioMode = .none }).total)
    }

    // Audio only: the resolution None.

    private var audioOnly: WhatWillBeRecorded { section { $0.resolution = .none } }

    @Test func atTheResolutionNoneTheSettingsLineSaysThatNoScreenIsRecorded() {
        #expect(audioOnly.settingsLine
            == "Settings: resolution None (no screen is recorded), audio mode Default microphone (only the default microphone is recorded), system audio on")
        #expect(section { $0.resolution = .none; $0.audioMode = .wired }.settingsLine
            == "Settings: resolution None (no screen is recorded), audio mode Wired, system audio on")
    }

    /// The screens are rows not recorded, without a number, Records at and GB/h max; the total is the audio files'.
    @Test func atTheResolutionNoneTheScreensAreRowsNotRecordedAndTheTotalIsTheAudios() {
        #expect(audioOnly.screenRows == [
            .init(source: .screen(nil, name: "Built-in Retina Display"), values: ["1728×1117", "3456×2234", "-", "-"], isRecorded: false),
            .init(source: .screen(nil, name: "LG HDR 4K"), values: ["3840×2160", "3840×2160", "-", "-"], isRecorded: false),
        ])
        #expect(audioOnly.audio == section().audio)
        #expect(audioOnly.total == .init(gigabytesPerHour: "0.1", need: "2 hours need 0.3 GB, 3.1 GB free."))
    }

    @Test func atTheResolutionNoneUnreadableScreensKeepTheTotal() {
        let broken = section({ $0.resolution = .none }, screens: .failure(DeviceReadError("no screen")))
        #expect(broken.screensError == "The screens cannot be read: no screen")
        #expect(broken.total == audioOnly.total)
    }

    /// A screen not recorded keeps its name's column, the `Screen <n> - ` part blank, as an audio source not recorded does.
    @Test func atTheResolutionNoneTheTextKeepsTheScreensNamesColumn() {
        #expect(section({ $0.resolution = .none }, audioInputs: []).text == """
            What will be recorded
              Settings: resolution None (no screen is recorded), audio mode Default microphone (only the default microphone is recorded), system audio on
              Source                              Looks like  Drawn at   Records at  GB/h max
              ───────────────────────────────────────────────────────────────────────────────
                         Built-in Retina Display  1728×1117   3456×2234  -                  -
                         LG HDR 4K                3840×2160   3840×2160  -                  -
              ───────────────────────────────────────────────────────────────────────────────
              Audio 0 - System                                           stereo           0.1
              ───────────────────────────────────────────────────────────────────────────────
              Total                                                                       0.1
              2 hours need 0.2 GB, 3.1 GB free.
              Files go to ~/Movies/Multi Screen Recorder

            """)
    }
}
