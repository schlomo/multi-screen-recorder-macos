import AppKit
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

    @Test func theStatusWindowWidensForALongName() {
        #expect(width(status(statusModel(name: "Mic", cpu: "")))
            < width(status(statusModel(name: String(repeating: "CalDigit Thunderbolt 3 Audio ", count: 3), cpu: ""))))
    }
}
