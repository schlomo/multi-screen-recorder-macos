import AppKit
import RecorderCore
import RecorderLogic
import SwiftUI
import Testing
@testable import msr

/// Each window is as wide as its table, or its header, needs: no table cell
/// wraps or is cut, and the text below the table wraps to that width.
@MainActor
@Suite struct WindowWidthTests {
    private static let screens = [
        ScreenInfo(name: "DELL P3421W", pixelSize: FrameSize(width: 3440, height: 1440), pointSize: FrameSize(width: 3440, height: 1440), isMain: true, originX: 0, originY: 0),
    ]

    private func width(_ view: some View) -> CGFloat {
        _ = NSApplication.shared
        return NSHostingController(rootView: view).view.fittingSize.width
    }

    private func section(inputName: String, screensError: Bool = false) -> WhatWillBeRecorded {
        WhatWillBeRecorded(
            settings: .defaults,
            screens: screensError ? .failure(DeviceReadError(String(repeating: "the screen list is missing ", count: 8))) : .success(Self.screens),
            audioInputs: .success([AudioInputInfo(name: inputName, channelCount: 2, isDefault: true, transport: .usb, uid: "A")]),
            outputFolder: .usable(.bytes(100_000_000_000)))
    }

    private func table(_ section: WhatWillBeRecorded) -> some View {
        WhatWillBeRecordedView(section: section, outputFolder: Settings.defaults.outputFolder) {}
    }

    @Test func theStartWindowsTableNarrowsToShortNames() {
        #expect(width(table(section(inputName: "Mic"))) < width(table(section(inputName: "CalDigit Thunderbolt 3 Audio"))))
    }

    @Test func aLongMessageAboveOrBelowTheTableWrapsInsteadOfWidening() {
        // The input's name is the longest either way, so Source is as wide.
        let name = "CalDigit Thunderbolt 3 Audio"
        #expect(width(table(section(inputName: name, screensError: true))) == width(table(section(inputName: name))))
    }

    // MARK: The start window

    private static let shortScreens = [
        ScreenInfo(name: "LG", pixelSize: FrameSize(width: 3840, height: 2160), pointSize: FrameSize(width: 3840, height: 2160), isMain: true, originX: 0, originY: 0),
    ]
    private static let inputs = [
        AudioInputInfo(name: "CalDigit Thunderbolt 3 Audio", channelCount: 2, isDefault: false, transport: .usb, uid: "A"),
        AudioInputInfo(name: "MacBook Pro Microphone", channelCount: 1, isDefault: true, transport: .builtIn, uid: "B"),
        AudioInputInfo(name: "AirPods Pro", channelCount: 1, isDefault: false, transport: .bluetooth, uid: "C"),
    ]

    /// Holds each start window model's own home folder; a test that makes one removes it at its end.
    private let home = FileManager.default.temporaryDirectory.appending(path: "WindowWidth-\(UUID().uuidString)", directoryHint: .isDirectory)

    /// The start window's model with stand-in probes, its ready check run and the settings changed.
    private func startModel(screens: [ScreenInfo], inputs: [AudioInputInfo], _ edit: (inout RecorderLogic.Settings) -> Void = { _ in }) async throws -> StartModel {
        let home = home.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let probes = ReadyCheckProbes(
            screenRecording: { _ in .granted }, microphonePermission: { true },
            screens: { .success(screens) }, audioInputs: { .success(inputs) },
            outputFolder: { _ in .usable(.bytes(100_000_000_000)) })
        let model = StartModel(homeFolder: home, probes: probes, whenContentMayChange: { $0() })
        model.load()
        model.change(edit)
        for _ in 0..<600 where model.isChecking || model.readyCheck == nil { try? await Task.sleep(for: .milliseconds(5)) }
        try #require(model.readyCheck != nil && !model.isChecking, "the ready check did not finish within 3 s")
        return model
    }

    private func start(_ model: StartModel) -> some View {
        StartView(model: model) {}
    }

    @Test func aSettingDoesNotChangeTheStartWindowsWidth() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let auto = try await startModel(screens: Self.screens, inputs: Self.inputs) { $0.auto = true }
        let none = try await startModel(screens: Self.screens, inputs: Self.inputs) { $0.auto = false; $0.audioMode = .none }
        let all = try await startModel(screens: Self.screens, inputs: Self.inputs) { $0.auto = false; $0.audioMode = .allInputs }
        let widths = [width(start(auto)), width(start(none)), width(start(all))]
        #expect(Set(widths).count == 1, "\(widths)")
    }

    @Test func theStartWindowIsAsWideAsItsTableAndTheTextBelowWraps() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let model = try await startModel(screens: Self.screens, inputs: Self.inputs)
        let section = try #require(model.whatWillBeRecorded)
        let tableWidth = width(WhatWillBeRecordedView(section: section, outputFolder: model.settings.outputFolder) {})
        #expect(tableWidth > width(AppHeader()))
        #expect(width(start(model)) == tableWidth + 2 * TableLayout.windowPadding)
        // The audio mode's explanation, on one line, would be wider.
        let explanation = (AudioMode.bluetoothAndVirtualNote as NSString)
            .size(withAttributes: [.font: NSFont.preferredFont(forTextStyle: .callout)]).width
        #expect(explanation > tableWidth)
    }

    @Test func whenTheTaglineHeaderIsWiderThanTheTableItSetsTheWidth() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let model = try await startModel(screens: Self.shortScreens, inputs: [])
        let section = try #require(model.whatWillBeRecorded)
        let tableWidth = width(WhatWillBeRecordedView(section: section, outputFolder: model.settings.outputFolder) {})
        #expect(width(AppHeader()) > tableWidth)
        #expect(width(start(model)) == width(AppHeader()) + 2 * TableLayout.windowPadding)
    }

    /// Through the start window this cannot fail today: the header is wider
    /// than the settings form needs at least. So the rule is held on the
    /// layout the window is built on.
    @Test func aWidthSettingStackIsNeverNarrowerThanItsOtherChildrenNeed() {
        let stack = WidthSettingStack(spacing: 0) {
            Color.clear.frame(width: 100, height: 10).setsTheWidth()
            Color.clear.frame(minWidth: 300, maxWidth: .infinity, minHeight: 10)
            Text(String(repeating: "wraps ", count: 100))
        }
        #expect(width(stack) == 300)
    }

    private func statusModel(name: String, cpu: String) -> StatusModel {
        let model = StatusModel()
        model.rows = [.init(source: .audioInput(1, name: name), recordsAt: "2 channels", files: 1, written: "40 MB", state: "recording")]
        model.line = "0:01:00, 40 MB in 1 file, 100 GB free"
        model.cpu = cpu
        return model
    }

    private func status(_ model: StatusModel) -> some View {
        StatusView(model: model, stop: {}, continueRecording: {})
    }

    @Test func theCPUExplanationWrapsInsteadOfWideningTheStatusWindow() {
        let long = "CalDigit Thunderbolt 3 Audio"
        #expect(width(status(statusModel(name: long, cpu: "CPU 23 %"))) == width(status(statusModel(name: long, cpu: ""))))
    }

    /// Only the source names move it: a state, a size written or a count of files changes nothing.
    @Test func theStatusWindowKeepsItsWidthWhileItRecords() {
        func model(state: String, written: String, files: Int) -> StatusModel {
            let model = statusModel(name: "Mic", cpu: "CPU 3 %")
            model.rows[0].state = state
            model.rows[0].written = written
            model.rows[0].files = files
            return model
        }
        let widths = [
            model(state: "recording", written: "0 MB", files: 1),
            model(state: "shows another screen", written: "888.8 GB", files: 888),
            model(state: "failed, retrying", written: "10.2 GB", files: 10),
            model(state: "?", written: "?", files: 9),
        ].map { width(status($0)) }
        #expect(Set(widths).count == 1, "\(widths)")
    }

    @Test func theStatusWindowWidensForALongName() {
        #expect(width(status(statusModel(name: "Mic", cpu: "")))
            < width(status(statusModel(name: String(repeating: "CalDigit Thunderbolt 3 Audio ", count: 3), cpu: ""))))
    }
}
