/// The window's section "What will be recorded", from the settings and the
/// devices connected now, as data the view renders.
public struct WhatWillBeRecorded: Equatable, Sendable {
    public struct Display: Equatable, Sendable {
        public var number: Int
        public var name: String
        public var size: String
        public var recordsAt: String
    }

    public struct AudioInput: Equatable, Sendable {
        public var name: String
        public var channels: String
        /// The input Start records; every other one is shown dimmed.
        public var isRecorded: Bool
        public var note: String?
    }

    /// Set when the devices cannot be read; the section then shows no rows.
    public var devicesError: String?
    public var displays: [Display]
    public var audioInputs: [AudioInput]
    /// Set when the audio mode records no microphone.
    public var microphoneNote: String?
    public var systemAudio: String
    public var outputFolder: String
    public var continuity: String

    public init(
        devicesError: String?, displays: [Display], audioInputs: [AudioInput], microphoneNote: String?,
        systemAudio: String, outputFolder: String, continuity: String
    ) {
        self.devicesError = devicesError
        self.displays = displays
        self.audioInputs = audioInputs
        self.microphoneNote = microphoneNote
        self.systemAudio = systemAudio
        self.outputFolder = outputFolder
        self.continuity = continuity
    }

    public init(
        settings: Settings,
        displays readDisplays: Result<[DisplayInfo], DeviceReadError>,
        audioInputs readAudioInputs: Result<[AudioInputInfo], DeviceReadError>
    ) {
        self.init(
            devicesError: nil, displays: [], audioInputs: [],
            microphoneNote: settings.audioMode == .none ? "The microphone is not recorded: the audio mode is None." : nil,
            systemAudio: settings.systemAudio ? "System audio: recorded" : "System audio: off",
            outputFolder: "Files go to \(settings.outputFolder)",
            continuity: "Recording continues when displays or audio sources change.")
        switch (readDisplays, readAudioInputs) {
        case (.success(let displayInfos), .success(let inputs)):
            displays = numberDisplays(displayInfos).map { numbered in
                Display(
                    number: numbered.number, name: numbered.display.name, size: numbered.display.sizeText,
                    recordsAt: "records at \(settings.resolution.frameSize(forDisplay: numbered.display.pixelSize))")
            }
            audioInputs = inputs.map { input in
                let isRecorded = settings.audioMode == .defaultMicrophone && input.isDefault
                return AudioInput(
                    name: input.name, channels: input.channelsText, isRecorded: isRecorded,
                    note: isRecorded || settings.audioMode == .none ? nil : "not recorded in this version")
            }
        case (.failure(let error), _), (_, .failure(let error)):
            devicesError = "The devices cannot be read: \(error)"
        }
    }
}
