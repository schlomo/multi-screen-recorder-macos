import Testing
@testable import RecorderLogic

@Suite struct WhatWillBeRecordedTests {
    private func section(
        _ edit: (inout Settings) -> Void = { _ in },
        displays: Result<[DisplayInfo], DeviceReadError> = .success(DesignExample.displays),
        audioInputs: Result<[AudioInputInfo], DeviceReadError> = .success(DesignExample.audioInputs)
    ) -> WhatWillBeRecorded {
        var settings = Settings.defaults
        edit(&settings)
        return WhatWillBeRecorded(settings: settings, displays: displays, audioInputs: audioInputs)
    }

    @Test func theDefaultsWithTheDesignsDevices() {
        #expect(section() == WhatWillBeRecorded(
            devicesError: nil,
            displays: [
                .init(number: 1, name: "Built-in Retina Display", size: "looks like 1728×1117, drawn at 3456×2234",
                      recordsAt: "records at 1670×1080"),
                .init(number: 2, name: "LG HDR 4K", size: "3840×2160", recordsAt: "records at 1920×1080"),
            ],
            audioInputs: [
                .init(name: "MacBook Pro Microphone", channels: "1 channel", isRecorded: true, note: nil),
                .init(name: "RØDE Wireless GO II RX", channels: "2 channels", isRecorded: false,
                      note: "not recorded in this version"),
            ],
            microphoneNote: nil,
            systemAudio: "System audio: recorded",
            outputFolder: "Files go to ~/Movies/Multi Screen Recorder",
            continuity: "Recording continues when displays or audio sources change."))
    }

    @Test func recordsAtFollowsTheResolution() {
        #expect(section { $0.resolution = .native }.displays.map(\.recordsAt)
            == ["records at 3456×2234", "records at 3840×2160"])
    }

    @Test func audioModeNoneDimsEveryInputAndSaysSo() {
        let none = section { $0.audioMode = .none }
        #expect(none.audioInputs.allSatisfy { !$0.isRecorded && $0.note == nil })
        #expect(none.microphoneNote == "The microphone is not recorded: the audio mode is None.")
    }

    @Test func noInputIsRecordedWithoutADefault() {
        let inputs = DesignExample.audioInputs.map {
            AudioInputInfo(name: $0.name, channelCount: $0.channelCount, isDefault: false)
        }
        #expect(section(audioInputs: .success(inputs)).audioInputs.allSatisfy { !$0.isRecorded })
    }

    @Test func systemAudioOff() {
        #expect(section { $0.systemAudio = false }.systemAudio == "System audio: off")
    }

    @Test func theOutputFolderIsAsSet() {
        #expect(section { $0.outputFolder = "/Volumes/Data/Recordings" }.outputFolder
            == "Files go to /Volumes/Data/Recordings")
    }

    @Test func unreadableDevicesShowTheErrorOnceAndNoRows() {
        let error = DeviceReadError("the display X does not report its display mode")
        for broken in [
            section(displays: .failure(error)),
            section(audioInputs: .failure(error)),
            section(displays: .failure(error), audioInputs: .failure(DeviceReadError("other"))),
        ] {
            #expect(broken.devicesError == "The devices cannot be read: the display X does not report its display mode")
            #expect(broken.displays.isEmpty)
            #expect(broken.audioInputs.isEmpty)
        }
    }
}
