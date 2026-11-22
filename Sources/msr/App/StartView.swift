import AppKit
import RecorderCore
import RecorderLogic
import SwiftUI

struct StartView: View {
    let model: StartModel
    let start: () -> Void

    var body: some View {
        WidthSettingStack(spacing: 16) {
            AppHeader().setsTheWidth()
            Divider()
            if let section = model.whatWillBeRecorded {
                WhatWillBeRecordedView(section: section, outputFolder: model.settings.outputFolder) {
                    openOutputFolder()
                }
                .setsTheWidth()
            }
            Divider()
            SettingsForm(model: model)
            Divider()
            ReadyCheckView(result: model.readyCheck, isChecking: model.isChecking) { model.checkAgain() }
            Divider()
            HStack {
                Spacer()
                // Quits without recording, as Cmd-Q does.
                Button("Cancel") { NSApp.terminate(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Start", action: start)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStart)
            }
        }
        .padding(TableLayout.windowPadding)
    }

    private func openOutputFolder() {
        let folder = model.settings.outputFolderURL(homeFolder: model.homeFolder)
        guard !NSWorkspace.shared.open(folder) else { return }
        let alert = NSAlert()
        alert.messageText = "Cannot open the output folder"
        alert.informativeText = "Finder cannot open \(folder.path(percentEncoded: false))."
        alert.runModal()
    }
}

/// The slim light frame around the icon's graphite tile in dark mode, where
/// the tile has almost no edge against the window: the tile's shape in
/// `assets/icon/app-icon.svg`, scaled to the icon's size.
struct IconTileFrame {
    static let viewBox = 372.82
    static let tileSize = 300.0
    static let tileCornerRadius = 67.0

    let iconSize: Double
    let lineWidth = 1.0
    let opacity = 0.25

    var inset: Double { (Self.viewBox - Self.tileSize) / 2 * iconSize / Self.viewBox }
    var cornerRadius: Double { Self.tileCornerRadius * iconSize / Self.viewBox }
}

/// The app icon, the name, the version and the homepage, and the tagline.
struct AppHeader: View {
    private static let iconSize = 48.0
    private let tileFrame = IconTileFrame(iconSize: iconSize)
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .overlay {
                    if colorScheme == .dark {
                        RoundedRectangle(cornerRadius: tileFrame.cornerRadius)
                            .stroke(.white.opacity(tileFrame.opacity), lineWidth: tileFrame.lineWidth)
                            .padding(tileFrame.inset)
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Multi Screen Recorder").font(.title2.bold())
                Text(runningVersion.description)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Link(Homepage.url.host() ?? Homepage.url.absoluteString, destination: Homepage.url)
            }
            Spacer(minLength: 12)
            // Each line whole: the header sets the window's width when it is wider than the table.
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(Tagline.lines, id: \.self) { line in
                    Text(line).fixedSize()
                }
            }
            .italic()
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
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
                Text("Every screen at Native, the audio mode Wired, the camera mode All real.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .opacity(model.settings.auto ? 1 : 0)
                    .accessibilityHidden(!model.settings.auto)
                LabeledContent("Recording resolution") {
                    HStack {
                        Slider(value: resolutionIndex, in: 0...Double(RecordingResolution.smallestFirst.count - 1), step: 1)
                            .accessibilityLabel("Recording resolution")
                            .accessibilityValue(model.settings.effectiveResolution.shownName)
                        Text(model.settings.effectiveResolution.shownName).frame(width: 60, alignment: .leading)
                            .accessibilityHidden(true)
                    }
                }
                .disabled(model.settings.auto)
                LabeledContent("Audio mode") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Slider(value: audioModeIndex, in: 0...Double(AudioMode.allCases.count - 1), step: 1)
                                .accessibilityLabel("Audio mode")
                                .accessibilityValue(model.settings.effectiveAudioMode.shownName)
                            Text(model.settings.effectiveAudioMode.shownName).frame(width: 130, alignment: .leading)
                                .accessibilityHidden(true)
                        }
                        Text(AudioMode.bluetoothAndVirtualNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(model.settings.auto)
                LabeledContent("Camera mode") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Slider(value: cameraModeIndex, in: 0...Double(CameraMode.allCases.count - 1), step: 1)
                                .accessibilityLabel("Camera mode")
                                .accessibilityValue(model.settings.effectiveCameraMode.shownName)
                            Text(model.settings.effectiveCameraMode.shownName).frame(width: 130, alignment: .leading)
                                .accessibilityHidden(true)
                        }
                        Text(CameraMode.leftOutNote)
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

    private var cameraModeIndex: Binding<Double> {
        Binding(
            get: { model.settings.effectiveCameraMode.sliderIndex },
            set: { position in
                guard let chosen = model.settings.cameraMode.choosing(sliderPosition: position) else { return }
                model.change { $0.cameraMode = chosen }
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

/// One table with a header, striped rows and a border: the screens, the
/// cameras, the audio sources and the total.
struct WhatWillBeRecordedView: View {
    let section: WhatWillBeRecorded
    /// The output folder as the settings name it, a link that opens it in Finder.
    let outputFolder: String
    let openOutputFolder: () -> Void

    var body: some View {
        WidthSettingStack(spacing: 6) {
            Text("What will be recorded").font(.headline)
            if let error = section.screensError { errorLabel(error) }
            if let error = section.audioError { errorLabel(error) }
            VStack(spacing: 0) {
                row(nil, WhatWillBeRecorded.columns)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .background(.quaternary.opacity(0.5))
                Divider()
                ForEach(Array(section.screenRows.enumerated()), id: \.offset) { index, screenRow in
                    row(screenRow)
                        .foregroundStyle(screenRow.isRecorded ? .primary : .tertiary)
                        .background(stripe(index))
                }
                if !section.screenRows.isEmpty { Divider() }
                ForEach(Array(section.cameraRows.enumerated()), id: \.offset) { index, cameraRow in
                    row(cameraRow)
                        .foregroundStyle(cameraRow.isRecorded ? .primary : .tertiary)
                        .background(stripe(section.screenRows.count + index))
                }
                if !section.cameraRows.isEmpty { Divider() }
                ForEach(Array(section.audioRows.enumerated()), id: \.offset) { index, audioRow in
                    row(audioRow)
                        .foregroundStyle(audioRow.isRecorded ? .primary : .tertiary)
                        .background(stripe(section.screenRows.count + section.cameraRows.count + index))
                }
                if let totalRow = section.totalRow {
                    Divider()
                    // Only "Total" is bold: bold digits are wider and
                    // would move the total's decimal point.
                    row(totalRow, boldSource: true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .setsTheWidth()
            if let need = section.total?.need { Text(need) }
            HStack(spacing: 4) {
                Text("Files go to")
                Button(outputFolder, action: openOutputFolder)
                    .buttonStyle(.link)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("Open in Finder")
            }
            Text(section.continuity).foregroundStyle(.secondary)
        }
    }

    private var sourceWidth: CGFloat {
        TableLayout.sourceWidth(names: (section.screenRows + section.cameraRows + section.audioRows).compactMap { $0.source?.name })
    }

    private func stripe(_ index: Int) -> Color {
        Color(nsColor: NSColor.alternatingContentBackgroundColors[index % NSColor.alternatingContentBackgroundColors.count])
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ row: WhatWillBeRecorded.Row, boldSource: Bool = false) -> some View {
        self.row(row.source, row.cells, boldSource: boldSource)
    }

    /// Digits of one width, so the GB/h max figures line up on the decimal
    /// point. A source shows its icon and number; the header and the total
    /// row have none.
    private func row(_ source: SourceCell?, _ cells: [String], boldSource: Bool = false) -> some View {
        HStack(spacing: TableLayout.columnSpacing) {
            ForEach(Array(cells.enumerated()), id: \.offset) { column, cell in
                if column == 0 {
                    Group {
                        if let source {
                            SourceCellView(cell: source, numberDigits: section.numberDigits)
                        } else {
                            Text(cell)
                                .fontWeight(boldSource ? .semibold : nil)
                                .lineLimit(1)
                        }
                    }
                    .frame(minWidth: sourceWidth, maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(cell)
                        .lineLimit(1)
                        .frame(width: TableLayout.fixedColumnWidths[column - 1],
                               alignment: column == cells.count - 1 ? .trailing : .leading)
                }
            }
        }
        .monospacedDigit()
        .padding(.horizontal, TableLayout.cellPadding)
        .padding(.vertical, 3)
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
