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
    var problems: [String] = []
}

/// The status window of a running recording (D46), in the app and in `msr
/// record`: opened by a click on the Dock icon or by Quit. Stop ends the
/// recording, Continue closes it.
@MainActor
final class StatusWindow {
    let model = StatusModel()
    private var window: NSWindow?
    private var onStop: (() -> Void)?

    var isOpen: Bool { window?.isVisible == true }

    func show(onStop: @escaping () -> Void) {
        self.onStop = onStop
        if window == nil {
            let hosting = NSHostingController(rootView: StatusView(
                model: model, stop: { [weak self] in self?.stop() }, continueRecording: { [weak self] in self?.close() }))
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
    static let forAReport = "For a report, \(RecordingNames.manifest) and \(RecordingNames.recordingLog) in the recording folder"
        + " show what happened; attach them to the issue."

    let model: StatusModel
    let stop: () -> Void
    let continueRecording: () -> Void

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
                }
                Divider()
                ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        SourceCellView(cell: row.source).monospacedDigit()
                        ForEach(Array(row.values.enumerated()), id: \.offset) { offset, cell in
                            Text(cell)
                                .lineLimit(1)
                                .monospacedDigit()
                                .gridColumnAlignment(Self.alignment(offset + 1))
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
                    ForEach(Array(model.problems.enumerated()), id: \.offset) { _, problem in
                        Text(problem).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
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

    /// Files and Written are right-aligned.
    private static func alignment(_ column: Int) -> HorizontalAlignment {
        column == 2 || column == 3 ? .trailing : .leading
    }
}
