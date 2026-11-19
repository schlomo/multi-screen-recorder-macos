import Foundation

/// The detail lines a recording log starts with, before the first event
/// (D64): the app and the recording folder, macOS and the Mac model, the
/// settings as the recording manifest has them, "What will be recorded"
/// line by line as `msr record` prints it, and the ready check's facts and
/// result. Nothing names the person, the host or a serial number.
public enum RecordingLogStart {
    public static func lines(
        app: String, recordingFolder: String, macOS: String, macModel: String?, settings: Settings, facts: ReadyCheckFacts
    ) -> [DetailLine.Entry] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let recorded = (try? encoder.encode(RecordingManifest.RecordedSettings(settings))).map { String(decoding: $0, as: UTF8.self) }
            ?? "cannot be encoded"
        let table = WhatWillBeRecorded(settings: settings, facts: facts).text
            .split(separator: "\n").map { DetailLine.Entry(category: "what will be recorded", message: String($0)) }
        let readyCheck = ReadyCheck.evaluate(facts, settings: settings).text
            .split(separator: "\n").map { DetailLine.Entry(category: "ready check", message: String($0)) }
        return [
            DetailLine.Entry(category: "recorder", message: "started: \(app), recording folder \(recordingFolder)"),
            DetailLine.Entry(category: "recorder", message: "macOS \(macOS), Mac model \(macModel ?? "unknown")"),
            DetailLine.Entry(category: "recorder", message: "settings: \(recorded)"),
        ] + table + [DetailLine.Entry(category: "ready check", message: DetailLine.facts(facts))] + readyCheck
    }
}
