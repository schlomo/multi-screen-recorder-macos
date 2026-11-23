import Foundation

/// The technical details of a source the start window's and the status
/// window's rows show on mouse-over: plain lines, "Label: value", the
/// source's full name first. A potential problem is a "Note:" line.
public enum SourceDetails {
    /// The colour a screen file and a camera file are tagged with (D24).
    static let recordedColour = "Colour: recorded as BT.709 (SDR), HEVC 8-bit"

    public static func screen(
        label: String, looksLike: FrameSize, drawnAt: FrameSize?, recordsAt: FrameSize?, refreshRate: Double?,
        displayID: UInt32, isMain: Bool
    ) -> String {
        var lines = [label, "Looks like: \(looksLike)"]
        if let drawnAt { lines.append("Drawn at: \(drawnAt)") }
        lines.append("Records at: " + (recordsAt.map { "\($0)" } ?? "not recorded"))
        if let refreshRate { lines.append("Refresh rate: \(number(refreshRate)) Hz") }
        lines += [recordedColour, "Display ID: \(displayID)", "Main screen: \(yesNo(isMain))"]
        return lines.joined(separator: "\n")
    }

    /// Without a recording resolution that records video, no format lines.
    public static func camera(label: String, _ camera: CameraInfo, settings: Settings) -> String {
        var lines = [label, "Kind: \(kind(camera)), unique ID \(camera.uniqueID)"]
        if camera.transport == .usb { lines.append("USB link: " + (camera.usbSpeed?.text ?? "cannot be read")) }
        let offered = camera.offeredFormats.isEmpty ? camera.formats : camera.offeredFormats
        lines.append("Offers: " + (offered.isEmpty ? "no format" : offered.map(\.rangeText).joined(separator: ", ")))
        var notes: [String] = []
        let resolution = settings.effectiveResolution
        if let format = camera.chosenFormat(resolution: resolution, limited: settings.limitCameras),
           let recordsAt = camera.frameSize(resolution: resolution, limited: settings.limitCameras) {
            let kept = camera.isRunningElsewhere && camera.activeFormat != nil
            lines.append("Format: \(format), " + (kept ? "kept: another app uses it" : reason(for: format, of: camera, settings: settings)))
            lines.append("Records at: \(recordsAt)")
            let rate: Double?
            if kept {
                rate = camera.activeFrameRates?.upperBound
                lines.append("Frame rate: as another app set it" + (camera.activeFrameRates.map { ", now \(CameraFormat.ratesText($0))" } ?? ""))
            } else {
                rate = CameraFormat.frameRate(
                    closestTo: Double(TickGrid.recording.framesPerSecond), in: [format.minFramesPerSecond...format.maxFramesPerSecond])
                lines.append("Frame rate: " + (rate.map { "\(number($0)) fps, set by the recorder" } ?? "cannot be read"))
            }
            let tickRate = TickGrid.recording.framesPerSecond
            if let rate, Int(rate.rounded()) < tickRate {
                notes.append("Note: runs at \(number(rate)) fps, below the file's \(tickRate): \(tickRate - Int(rate.rounded())) of every \(tickRate) frames repeat the one before")
            }
            if camera.transport == .usb, camera.usbSpeed?.isAtMostUSB2 == true,
               format.size.pixelCount > RecorderValues.cameraLargestSize.pixelCount {
                notes.append("Note: more than 1080p over a USB 2 link (480 Mb/s): the USB bus may overload and the camera stall")
            }
        }
        lines += ["In use by another app: \(yesNo(camera.isRunningElsewhere))", "Suspended: \(yesNo(camera.isSuspended))"]
        if camera.isRunningElsewhere {
            notes.append("Note: another app uses it: its format and frame rate are that app's, not the recorder's")
        }
        return (lines + notes).joined(separator: "\n")
    }

    public static func audioInput(label: String, _ input: AudioInputInfo) -> String {
        let volume = input.inputVolume.map { volume in
            (volume.value.map { "\(Int(($0 * 100).rounded())) %" } ?? "cannot be read")
                + (volume.isSettable ? ", can be set" : ", cannot be set")
        } ?? "none"
        return [
            label,
            "Channels: " + ((try? input.channelCount.get()).map(String.init) ?? input.channelsText),
            "Sample rate: " + (input.sampleRate.map(kilohertz) ?? "cannot be read")
                + ", recorded at \(kilohertz(Double(RecorderValues.audioSampleRate)))",
            "Connection: \(input.transport.shownName)",
            "Input volume: \(volume)",
            "Default microphone: \(yesNo(input.isDefault))",
            "UID: \(input.uid ?? "cannot be read")",
            "Records as: a mono AAC-LC track per channel, \(Encoding.audioInputTrackBitRate / 1000) kbit/s each",
        ].joined(separator: "\n")
    }

    public static func systemAudio(label: String) -> String {
        [
            label,
            "Captures: the sound the Mac plays, Multi Screen Recorder's own left out, through ScreenCaptureKit on the main screen",
            "Records as: a stereo AAC-LC track, \(kilohertz(Double(RecorderValues.audioSampleRate))), "
                + "\(Encoding.systemAudioTrackBitRate / 1000) kbit/s",
        ].joined(separator: "\n")
    }

    /// The status window's facts of a running capture, under the source's details:
    /// a video file's frames repeated for lateness and placed late so far, a
    /// camera's stall, an audio source's clock drift.
    public static func live(
        lateness: (repeated: Int, placedLate: Int)? = nil, isStalled: Bool? = nil, clockDrift: ClockDriftCorrection.Status? = nil
    ) -> [String] {
        var lines: [String] = []
        if let lateness {
            lines.append("This file so far: \(lateness.repeated) frame\(lateness.repeated == 1 ? "" : "s") repeated for lateness, "
                + "\(lateness.placedLate) placed late")
        }
        if let isStalled { lines.append("Stalled: \(yesNo(isStalled))") }
        if let clockDrift {
            lines.append("Clock drift: "
                + (clockDrift.clockDriftPpm.map { ClockDriftText.signed($0, decimals: 1, unit: "ppm") } ?? "not measured yet")
                + ", corrected \(ClockDriftText.signed(clockDrift.applied * 1000, decimals: 2, unit: "ms")) so far")
        }
        return lines
    }

    /// "USB", "built in", "iPhone" or "virtual".
    static func kind(_ camera: CameraInfo) -> String {
        if camera.isContinuity { return "iPhone" }
        if camera.isVirtual { return "virtual" }
        return camera.transport.shownName
    }

    /// Why the recorder chose `format` (D74).
    static func reason(for format: CameraFormat, of camera: CameraInfo, settings: Settings) -> String {
        let resolution = settings.effectiveResolution
        let fastEnough = camera.formats.filter(\.deliversTheTickRate)
        guard !fastEnough.isEmpty else { return "the fastest, as no format reaches \(TickGrid.recording.framesPerSecond) fps" }
        var reasons = ["the largest recorded size"]
        let limits = fastEnough.contains { format in
            resolution.cameraFrameSize(for: format.size, limited: false) != resolution.cameraFrameSize(for: format.size, limited: true)
        }
        if settings.limitCameras, limits { reasons.append("limited to 1080p") }
        if !settings.limitCameras { reasons.append("1080p limit off") }
        let recorded = { (format: CameraFormat) in resolution.cameraFrameSize(for: format.size, limited: settings.limitCameras).pixelCount }
        let tiedByTurn = fastEnough.contains { other in
            recorded(other) == recorded(format) && other.size.pixelCount == format.size.pixelCount
                && CameraInfo.turn(of: other.size) != CameraInfo.turn(of: format.size)
        }
        if tiedByTurn, camera.activeFormat != nil { reasons.append("turned as the camera's active format") }
        return reasons.joined(separator: ", ")
    }

    private static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    private static func number(_ value: Double) -> String { String(format: "%g", (value * 100).rounded() / 100) }

    private static func kilohertz(_ hertz: Double) -> String { "\(number(hertz / 1000)) kHz" }
}
