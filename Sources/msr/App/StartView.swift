import AppKit
import RecorderLogic
import SwiftUI

struct StartView: View {
    let model: StartModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let section = model.whatWillBeRecorded { WhatWillBeRecordedView(section: section) }
            Divider()
            SettingsForm(model: model)
            Divider()
            ReadyCheckView(result: model.readyCheck, isChecking: model.isChecking) { model.checkAgain() }
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

private struct SettingsForm: View {
    let model: StartModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.saveError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Form {
                Toggle("Auto", isOn: binding(\.auto))
                // Always shown, so that turning Auto on or off shifts nothing; Auto on disables the sliders.
                Text("Every display at Native, the audio mode Wired.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .opacity(model.settings.auto ? 1 : 0)
                LabeledContent("Recording resolution") {
                    HStack {
                        Slider(value: resolutionIndex, in: 0...Double(RecordingResolution.smallestFirst.count - 1), step: 1)
                            .accessibilityLabel("Recording resolution")
                            .accessibilityValue(model.settings.effectiveResolution.label)
                        Text(model.settings.effectiveResolution.label).frame(width: 60, alignment: .leading)
                            .accessibilityHidden(true)
                    }
                }
                .disabled(model.settings.auto)
                LabeledContent("Audio mode") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Slider(value: audioModeIndex, in: 0...Double(AudioMode.allCases.count - 1), step: 1)
                                .accessibilityLabel("Audio mode")
                                .accessibilityValue(model.settings.effectiveAudioMode.label)
                            Text(model.settings.effectiveAudioMode.label).frame(width: 130, alignment: .leading)
                                .accessibilityHidden(true)
                        }
                        Text(AudioMode.bluetoothAndVirtualNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(model.settings.auto)
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
    }

    private var resolutionIndex: Binding<Double> {
        Binding(
            get: { model.settings.effectiveResolution.sliderIndex },
            set: { position in
                guard let chosen = model.settings.resolution.choosing(sliderPosition: position) else { return }
                model.change { $0.resolution = chosen }
            })
    }

    private var audioModeIndex: Binding<Double> {
        Binding(
            get: { model.settings.effectiveAudioMode.sliderIndex },
            set: { position in
                guard let chosen = model.settings.audioMode.choosing(sliderPosition: position) else { return }
                model.change { $0.audioMode = chosen }
            })
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
        VStack(alignment: .leading, spacing: 6) {
            Text("What will be recorded").font(.headline)
            if let error = section.displaysError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    header(WhatWillBeRecorded.displayColumns)
                    ForEach(section.displays, id: \.number) { display in
                        GridRow {
                            Text("\(display.number)  \(display.name)")
                            Text(display.looksLike)
                            Text(display.drawnAt)
                            Text(display.recordsAt)
                            Text(display.gigabytesPerHour).gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
            if let error = section.audioError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                header(WhatWillBeRecorded.audioColumns)
                ForEach(Array(section.audio.enumerated()), id: \.offset) { _, source in
                    GridRow {
                        Text(source.name)
                        Text(source.channels)
                        Text(source.gigabytesPerHour).gridColumnAlignment(.trailing)
                    }
                    .foregroundStyle(source.isRecorded ? .primary : .tertiary)
                }
            }
            if let total = section.total { Text(total) }
            Text(section.outputFolder)
            Text(section.continuity).foregroundStyle(.secondary)
        }
    }

    private func header(_ columns: [String]) -> some View {
        GridRow {
            ForEach(columns, id: \.self) { Text($0) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
                Button("Check again", action: checkAgain)
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
