import AppKit
import RecorderLogic
import SwiftUI

struct StartView: View {
    let model: StartModel
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let section = model.whatWillBeRecorded { WhatWillBeRecordedView(section: section) }
            Divider()
            SettingsForm(model: model)
            Divider()
            ReadyCheckView(result: model.readyCheck, isChecking: model.isChecking) { model.checkAgain() }
            Divider()
            Button("Start", action: start)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStart)
        }
        .padding(20)
        .frame(width: TableLayout.windowWidth)
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
                    .accessibilityHidden(!model.settings.auto)
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
            if let error = section.displaysError { errorLabel(error) }
            if let error = section.audioError { errorLabel(error) }
            Grid(alignment: .leading, horizontalSpacing: TableLayout.columnSpacing, verticalSpacing: 2) {
                row(WhatWillBeRecorded.columns).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(section.displayRows.enumerated()), id: \.offset) { _, displayRow in
                    row(displayRow.cells)
                }
                if !section.displayRows.isEmpty { Divider() }
                ForEach(Array(section.audioRows.enumerated()), id: \.offset) { _, audioRow in
                    row(audioRow.cells).foregroundStyle(audioRow.isRecorded ? .primary : .tertiary)
                }
            }
            if let total = section.total { Text(total) }
            Text(section.outputFolder)
            Text(section.continuity).foregroundStyle(.secondary)
        }
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ cells: [String]) -> some View {
        GridRow {
            ForEach(Array(cells.enumerated()), id: \.offset) { column, cell in
                if column == 0 {
                    Text(cell)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(cell)
                        .frame(width: TableLayout.sourceWidth, alignment: .leading)
                } else {
                    Text(cell)
                        .lineLimit(1)
                        .frame(width: TableLayout.fixedColumnWidths[column - 1],
                               alignment: column == cells.count - 1 ? .trailing : .leading)
                }
            }
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
