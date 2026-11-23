import Foundation

/// The detail lines a recording log starts with, before the first event
/// (D64): the app and the recording folder, macOS and the Mac model, the
/// effective settings as `msr settings` prints them, "What will be recorded"
/// line by line as `msr record` prints it, and the ready check's facts and
/// result. Nothing names the person, the host or a serial number.
public enum RecordingLogStart {
    public static func lines(
        app: String, recordingFolder: String, macOS: String, macModel: String?, settings: Settings, facts: ReadyCheckFacts
    ) throws -> [DetailLine.Entry] {
        let effective = String(decoding: try settings.jsonData(), as: UTF8.self)
            .split(separator: "\n").map { DetailLine.Entry(category: "settings", message: String($0)) }
        let table = WhatWillBeRecorded(settings: settings, facts: facts).text
            .split(separator: "\n").map { DetailLine.Entry(category: "what will be recorded", message: String($0)) }
        let readyCheck = ReadyCheck.evaluate(facts, settings: settings).text
            .split(separator: "\n").map { DetailLine.Entry(category: "ready check", message: String($0)) }
        return [
            DetailLine.Entry(category: "recorder", message: "started: \(app), recording folder \(recordingFolder)"),
            DetailLine.Entry(category: "recorder", message: "macOS \(macOS), Mac model \(macModel ?? "unknown")"),
        ] + effective + table + [DetailLine.Entry(category: "ready check", message: DetailLine.facts(facts, resolution: settings.effectiveResolution, limitCameras: settings.limitCameras))] + readyCheck
    }
}
