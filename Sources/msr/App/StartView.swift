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
                SettingsForm(model: model)
                Divider()
                ReadyCheckView(result: model.readyCheck, isChecking: model.isChecking)
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

private struct ReadyCheckView: View {
    let result: ReadyCheckResult?
    let isChecking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ready check").font(.headline)
                if isChecking { ProgressView().controlSize(.small) }
            }
            if let result {
                ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                    ReadyCheckItemRow(item: item)
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

extension RecordingResolution {
    var label: String {
        switch self {
        case .native: "Native"
        case .uhd4k: "4K"
        case .p1440, .p1200, .p1080, .p720: rawValue
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
