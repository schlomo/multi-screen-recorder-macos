import Foundation
import Testing
@testable import EndToEndLogic

@Suite struct ScenarioTests {
    @Test func theNamedScenariosHaveUniqueNamesAndTheirEventsInOrder() {
        let names = Scenario.named.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names == ["plain-recording", "virtual-screen", "virtual-screen-stress", "tone", "system-audio", "stop-by-ctrl-c", "stop-by-kill"])
        for scenario in Scenario.named {
            #expect(scenario.events.map(\.at) == scenario.events.map(\.at).sorted())
            #expect(scenario.events.allSatisfy { $0.at < scenario.stopAt })
        }
    }

    @Test func eachVirtualScreenEndsAtTheSizeItStarted() {
        // macOS brings an identity back at its last mode: a scenario leaves it at its first.
        for scenario in Scenario.named {
            var sizes: [UInt32: (first: ScreenSize, now: ScreenSize)] = [:]
            for (_, event) in scenario.events {
                switch event {
                case .connectScreen(let spec): sizes[spec.serialNumber] = (spec.sizes[0], spec.sizes[0])
                case .switchScreenMode(let serial, let size): sizes[serial]?.now = size
                case .disconnectScreen(let serial):
                    #expect(sizes[serial].map { $0.first == $0.now } == true)
                }
            }
        }
    }

    @Test func theRecordCommandCarriesTheFolderTheFlagsAndADuration() {
        let plain = Scenario.named[0]
        #expect(plain.arguments(outputFolder: "/s") == ["record", "--output-folder", "/s", "--duration", "8s"])
        let tone = Scenario.named.first { $0.name == "tone" }!
        #expect(tone.arguments(outputFolder: "/s") == [
            "record", "--output-folder", "/s", "--resolution", "1080p", "--audio-mode", "default-microphone", "--system-audio", "off",
            "--duration", "130s",
        ])
    }

    /// The tone scenarios record only the default microphone, BlackHole, so it is the anchor (D80).
    @Test func theToneScenariosRecordOnlyTheDefaultMicrophone() {
        for name in ["tone", "system-audio"] {
            let scenario = Scenario.named.first { $0.name == name }!
            #expect(scenario.settings.audioMode == "default-microphone")
            #expect(scenario.playsTone)
        }
    }

    @Test func onlyTheVirtualScreenScenariosRecordWithDebugDetail() {
        // Their msr.err keeps the recorder's detail on the screens for a later look.
        #expect(Scenario.named.filter { $0.flags.contains("--debug") }.map(\.name) == ["virtual-screen", "virtual-screen-stress"])
    }

    @Test func theStressScenarioSwitchesTenTimesAboutTwoSecondsApart() throws {
        let stress = try #require(Scenario.named.first { $0.name == "virtual-screen-stress" })
        let switches = stress.events.filter { if case .switchScreenMode = $0.event { true } else { false } }
        #expect(switches.count == 10)
        #expect(zip(switches, switches.dropFirst()).allSatisfy { $1.at - $0.at == 2 })
        let sizes = switches.compactMap { entry -> ScreenSize? in
            if case .switchScreenMode(_, let size) = entry.event { size } else { nil }
        }
        #expect(sizes.map(\.description) == Array(repeating: ["1600x900", "1280x720"], count: 5).flatMap { $0 })
        #expect(stress.events.first.map { if case .connectScreen = $0.event { true } else { false } } == true)
        #expect(stress.events.last.map { if case .disconnectScreen = $0.event { true } else { false } } == true)
    }

    @Test func everyRecordingHasACeilingSoAKilledDriverNeverLeavesItRunning() throws {
        for scenario in Scenario.named {
            let arguments = scenario.arguments(outputFolder: "/s")
            let index = try #require(arguments.firstIndex(of: "--duration"))
            let ceiling = try #require(Double(arguments[index + 1].dropLast()))
            switch scenario.stop {
            case .duration: #expect(ceiling == scenario.stopAt)
            case .interrupt, .kill:
                #expect(ceiling == scenario.stopAt + Scenario.ceilingMargin)
                #expect(scenario.stopAt < ceiling)
            }
        }
        #expect(Scenario.ceilingMargin == 120)
    }

    @Test func aSettledTimeComesTheSettleTimeAfterTheChange() {
        let change = ChangeTimes(asked: 6.0, done: 6.25)
        let window = change.window(.settled, settleTime: 1, tolerance: 0.5, firstFrameLimit: 1)
        #expect(window == 6.5...7.75)
        #expect(window.contains(6.5) && window.contains(7.75))
        #expect(!window.contains(6.49) && !window.contains(7.76))
        #expect(change.windowWidth(.settled, settleTime: 1, tolerance: 0.5, firstFrameLimit: 1) == 1.25)
    }

    @Test func aFileStartComesTheSettleTimeAfterTheChangeThenItsFirstFrame() {
        let change = ChangeTimes(asked: 6.0, done: 6.25, lastChange: 6.125)
        let window = change.window(.started, settleTime: 1, tolerance: 0.5, firstFrameLimit: 1)
        #expect(window == 6.625...8.125)
        #expect(window.contains(7.125 + 0.875) && !window.contains(7.125 + 1.125))
        #expect(!window.contains(6.5))
    }

    @Test func anImmediateTimeComesWithTheChange() {
        let change = ChangeTimes(asked: 6.0, done: 6.25)
        let window = change.window(.immediate, settleTime: 1, tolerance: 0.5, firstFrameLimit: 1)
        #expect(window == 5.5...6.75)
        #expect(!window.contains(5.49) && !window.contains(6.76))
        #expect(change.windowWidth(.immediate, settleTime: 1, tolerance: 0.5, firstFrameLimit: 1) == 1.25)
    }

    @Test func aConnectAModeSwitchAndADisconnectGiveTheirFilesAndEvents() {
        let spec = VirtualScreenSpec(serialNumber: 101, name: "Portable Monitor", sizes: [.init(width: 1280, height: 720), .init(width: 1600, height: 900)])
        let expectation = Scenario.virtualScreenExpectation([
            HappenedEvent(times: .init(asked: 2.0, done: 2.2), event: .connectScreen(spec), screenUUID: "U"),
            HappenedEvent(times: .init(asked: 6.0, done: 6.2), event: .switchScreenMode(serialNumber: 101, to: spec.sizes[1]),
                          screenUUID: "U"),
            HappenedEvent(times: .init(asked: 11.0, done: 11.5), event: .disconnectScreen(serialNumber: 101)),
        ])
        let connect = ChangeTimes(asked: 2.0, done: 2.2)
        let modeSwitch = ChangeTimes(asked: 6.0, done: 6.2)
        let disconnect = ChangeTimes(asked: 11.0, done: 11.5)
        #expect(expectation.files == [
            .init(screenUUID: "U", frameSize: [1280, 720], startedBy: connect, noticedBy: 0, endedBy: .init(change: modeSwitch, kind: .settled)),
            .init(screenUUID: "U", frameSize: [1600, 900], startedBy: modeSwitch, noticedBy: nil, endedBy: .init(change: disconnect, kind: .immediate)),
        ])
        #expect(expectation.events == [
            .init(event: "screen connected", expected: .init(change: connect, kind: .immediate)),
            .init(event: "screen frame size changed", expected: .init(change: modeSwitch, kind: .settled)),
            .init(event: "screen disconnected", expected: .init(change: disconnect, kind: .immediate)),
        ])
    }

    @Test func aScreenStillConnectedAtTheStopHasNoDisconnect() {
        let spec = VirtualScreenSpec(serialNumber: 102, name: "Desk Monitor", sizes: [.init(width: 1280, height: 720)])
        let expectation = Scenario.virtualScreenExpectation([
            HappenedEvent(times: .init(asked: 1, done: 1.1), event: .connectScreen(spec), screenUUID: "V"),
        ])
        #expect(expectation.files.map(\.endedBy) == [nil])
        #expect(expectation.events.map(\.event) == ["screen connected"])
        #expect(spec.name == "Desk Monitor")
    }

    @Test func theStatusWindowsScreensComeBackSoAFileCountIsAboveOne() {
        let events = Scenario.statusWindowScreenEvents
        #expect(events.map(\.at) == events.map(\.at).sorted())
        var connected: Set<UInt32> = []
        var connects: [UInt32: Int] = [:]
        for (_, event) in events {
            switch event {
            case .connectScreen(let spec):
                #expect(connected.insert(spec.serialNumber).inserted)
                connects[spec.serialNumber, default: 0] += 1
            case .disconnectScreen(let serial): #expect(connected.remove(serial) != nil)
            case .switchScreenMode: Issue.record("the status window's screens switch no mode")
            }
        }
        #expect(connected.count >= 2, "several screens are connected at the capture")
        #expect(connects.values.contains { $0 > 1 }, "one screen came back")
    }

    @Test func theStatusWindowsScreensHaveIdentitiesOfTheirOwn() {
        let scenarioSerials = Scenario.named.flatMap(\.events).compactMap { _, event -> UInt32? in
            if case .connectScreen(let spec) = event { spec.serialNumber } else { nil }
        }
        let ownSerials = Scenario.statusWindowScreenEvents.compactMap { _, event -> UInt32? in
            if case .connectScreen(let spec) = event { spec.serialNumber } else { nil }
        }
        #expect(Set(ownSerials).isDisjoint(with: scenarioSerials))
    }
}
