import AppKit
import Observation
import RecorderLogic
import SwiftUI

/// What the status window shows, refreshed while it is open.
@MainActor
@Observable
final class StatusModel {
    var rows: [RecordingStatusTable.Row] = []
    var line = ""
    /// "CPU 23 %", our process only.
    var cpu = ""
    /// Red while ongoing, orange once recovered (D78).
    var problems: [ProblemLine] = []
    /// Each audio source's level meter, drawn 10 times a second while the window is open (D69).
    var levels: [AudioTracker.SourceID: AudioLevel] = [:]
    /// The input volume of each audio input whose volume can be set: only those have a slider.
    var inputVolumes: [AudioTracker.SourceID: Double] = [:]
}

/// The status window of a running recording (D46), in the app and in `msr
/// record`: opened by a click on the Dock icon or by Quit. Stop ends the
/// recording, Continue closes it; an audio input's slider sets its input volume (D69).
@MainActor
final class StatusWindow {
    let model = StatusModel()
    private var window: NSWindow?
    private var onStop: (() -> Void)?
    private var onInputVolume: ((AudioTracker.SourceID, Double) -> Void)?

    var isOpen: Bool { window?.isVisible == true }

    func show(onStop: @escaping () -> Void, onInputVolume: @escaping (AudioTracker.SourceID, Double) -> Void) {
        self.onStop = onStop
        self.onInputVolume = onInputVolume
        if window == nil {
            let hosting = NSHostingController(rootView: StatusView(
                model: model, stop: { [weak self] in self?.stop() }, continueRecording: { [weak self] in self?.close() },
                setInputVolume: { [weak self] id, volume in self?.onInputVolume?(id, volume) }))
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "Multi Screen Recorder"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func stop() {
        close()
        onStop?()
    }
}

struct StatusView: View {
    /// The line under the problems: the two files a report needs (D64).
    nonisolated static let forAReport = "For a report, \(RecordingNames.manifest) and \(RecordingNames.recordingLog) in the recording folder"
        + " show what happened; attach them to the issue."

    let model: StatusModel
    let stop: () -> Void
    let continueRecording: () -> Void
    let setInputVolume: (AudioTracker.SourceID, Double) -> Void
    /// The problem lines' height as laid out; the area shows at most `problemLinesShown` lines of it.
    @State var problemsHeight: CGFloat = 0

    /// The problems area grows to 5 lines at most; more scroll inside it (D78).
    static let problemLinesShown = 5
    private static let problemSpacing: CGFloat = 4
    private static var problemsMaxHeight: CGFloat {
        let lineHeight = NSLayoutManager().defaultLineHeight(for: NSFont.preferredFont(forTextStyle: .body))
        return CGFloat(problemLinesShown) * lineHeight + CGFloat(problemLinesShown - 1) * problemSpacing
    }

    var body: some View {
        WidthSettingStack(spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    ForEach(Array(RecordingStatusTable.columns.enumerated()), id: \.offset) { column, header in
                        if column == 0 {
                            Text(header).font(.headline)
                        } else {
                            Text(header).font(.headline)
                                .frame(minWidth: TableLayout.statusColumnWidths[column - 1], alignment: Alignment(horizontal: Self.alignment(column), vertical: .center))
                        }
                    }
                    ForEach(RecordingStatusTable.audioColumns, id: \.self) { header in
                        Text(header).font(.headline)
                    }
                }
                Divider()
                ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        SourceCellView(cell: row.source).monospacedDigit().help(row.details)
                        ForEach(Array(row.values.enumerated()), id: \.offset) { offset, cell in
                            Text(cell)
                                .lineLimit(1)
                                .monospacedDigit()
                                .gridColumnAlignment(Self.alignment(offset + 1))
                                .help(row.details)
                        }
                        if let id = row.audioSource {
                            LevelMeterView(level: model.levels[id] ?? .silent)
                            inputVolumeSlider(id, name: row.source.name)
                        } else {
                            Color.clear.frame(width: TableLayout.levelMeterWidth, height: 1)
                            Color.clear.frame(width: TableLayout.inputVolumeWidth, height: 1)
                        }
                    }
                }
            }
            .setsTheWidth()
            Text(model.line).monospacedDigit()
            if !model.cpu.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.cpu).monospacedDigit()
                    Text(CPUUsage.notCounted)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !model.problems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Self.problemSpacing) {
                            ForEach(Array(model.problems.enumerated()), id: \.offset) { _, problem in
                                Text(problem.text).foregroundStyle(problem.isRed ? .red : .orange).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { problemsHeight = $0 }
                    }
                    .frame(height: min(problemsHeight, Self.problemsMaxHeight))
                    Text(Self.forAReport)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Continue", action: continueRecording).keyboardShortcut(.cancelAction)
                Button("Stop", action: stop).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(TableLayout.windowPadding)
    }

    /// A slider only where the input volume can be set: no slider says so
    /// more clearly than a grey one, which reads as forbidden (D69).
    @ViewBuilder private func inputVolumeSlider(_ id: AudioTracker.SourceID, name: String) -> some View {
        if model.inputVolumes[id] != nil {
            Slider(value: Binding(
                get: { model.inputVolumes[id] ?? 0 },
                set: { volume in
                    model.inputVolumes[id] = volume
                    setInputVolume(id, volume)
                }), in: 0...1)
                .controlSize(.small)
                .frame(width: TableLayout.inputVolumeWidth)
                .accessibilityLabel("Input volume of \(name)")
        } else {
            Color.clear.frame(width: TableLayout.inputVolumeWidth, height: 1)
        }
    }

    /// Files and Written are right-aligned.
    private static func alignment(_ column: Int) -> HorizontalAlignment {
        column == 2 || column == 3 ? .trailing : .leading
    }
}
