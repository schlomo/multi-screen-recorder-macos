import AppKit
import RecorderLogic
import SwiftUI

struct StartView: View {
    let model: StartModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = model.settingsError {
                SettingsErrorView(message: error) { model.resetToDefaults() }
            } else {
                if let section = model.whatWillBeRecorded { WhatWillBeRecordedView(section: section) }
                Divider()
                SettingsForm(model: model)
                Divider()
                ReadyCheckView(result: model.readyCheck, isChecking: model.isChecking) { model.checkAgain() }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Button("Start") {}
                    .keyboardShortcut(.defaultAction)
                    .disabled(true)
                Text("This build cannot record yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

private struct SettingsErrorView: View {
    let message: String
    let reset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The settings file cannot be used", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.headline)
            Text(message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Reset to defaults", action: reset)
        }
    }
}

private struct SettingsForm: View {
    let model: StartModel

    var body: some View {
        Form {
            Picker("Recording resolution", selection: binding(\.resolution)) {
                ForEach(RecordingResolution.allCases, id: \.self) { Text($0.label) }
            }
            Picker("Audio mode", selection: binding(\.audioMode)) {
                ForEach(AudioMode.allCases, id: \.self) { Text($0.label) }
            }
            Toggle("System audio", isOn: binding(\.systemAudio))
            LabeledContent("Output folder") {
                HStack {
                    Text(model.settings.outputFolder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…", action: chooseOutputFolder)
                }
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RecorderLogic.Settings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.change { $0[keyPath: keyPath] = value } })
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.settings.outputFolderURL(homeFolder: model.homeFolder)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        model.chooseOutputFolder(folder)
    }
}

private struct WhatWillBeRecordedView: View {
    let section: WhatWillBeRecorded

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What will be recorded").font(.headline)
            if let error = section.devicesError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(section.displays, id: \.number) { display in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "display")
                    Text("\(display.number)  \(display.name)")
                    Text(display.size).foregroundStyle(.secondary)
                    Text(display.recordsAt)
                }
            }
            ForEach(Array(section.audioInputs.enumerated()), id: \.offset) { _, input in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: input.isRecorded ? "mic.fill" : "mic.slash")
                    Text("\(input.name), \(input.channels)")
                    if let note = input.note { Text(note).font(.callout) }
                }
                .foregroundStyle(input.isRecorded ? .primary : .tertiary)
            }
            if let note = section.microphoneNote { Text(note).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2")
                Text(section.systemAudio)
            }
            Text(section.outputFolder)
            Text(section.continuity).foregroundStyle(.secondary)
        }
    }
}

/// All green: one line "Ready to record" that expands on click. Any red:
/// every item, with the fix under each red one.
private struct ReadyCheckView: View {
    let result: ReadyCheckResult?
    let isChecking: Bool
    let checkAgain: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ready check").font(.headline)
                if isChecking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Check again", action: checkAgain).disabled(isChecking)
            }
            if let result {
                if result.isReady {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .foregroundStyle(.secondary)
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Ready to record")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !result.isReady || isExpanded {
                    ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                        ReadyCheckItemRow(item: item)
                    }
                }
            }
        }
    }
}

private struct ReadyCheckItemRow: View {
    let item: ReadyCheckItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(item.passed ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.passed, let fix = item.fix {
                    Text("Fix: \(fix)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension AudioMode {
    var label: String {
        switch self {
        case .none: "None"
        case .defaultMicrophone: "Default microphone"
        }
    }
}
