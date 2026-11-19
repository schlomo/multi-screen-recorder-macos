import Foundation
import Testing
@testable import EndToEndLogic

@Suite struct ScenarioTests {
    @Test func theNamedScenariosHaveUniqueNamesAndTheirEventsInOrder() {
        let names = Scenario.named.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names == ["plain-recording", "virtual-screen", "tone", "system-audio", "stop-by-ctrl-c", "stop-by-kill"])
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
            "record", "--output-folder", "/s", "--resolution", "1080p", "--audio-mode", "all-inputs", "--system-audio", "off",
            "--duration", "130s",
        ])
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

    @Test func aChangesWindowRunsFromTheAskToTheDonePlusTheSettleTime() {
        let change = ChangeTimes(asked: 6.0, done: 6.25)
        let window = change.window(settleTime: 1, tolerance: 0.5)
        #expect(window == 5.5...7.75)
        #expect(window.contains(5.5) && window.contains(7.75))
        #expect(!window.contains(5.49) && !window.contains(7.76))
        #expect(change.windowWidth(settleTime: 1, tolerance: 0.5) == 2.25)
    }

    @Test func aConnectAModeSwitchAndADisconnectGiveTheirFilesAndEvents() {
        let spec = VirtualScreenSpec(serialNumber: 101, sizes: [.init(width: 1280, height: 720), .init(width: 1600, height: 900)])
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
            .init(screenUUID: "U", frameSize: [1280, 720], startedBy: connect, endedBy: modeSwitch),
            .init(screenUUID: "U", frameSize: [1600, 900], startedBy: modeSwitch, endedBy: disconnect),
        ])
        #expect(expectation.events == [
            .init(event: "screen connected", change: connect), .init(event: "screen frame size changed", change: modeSwitch),
            .init(event: "screen disconnected", change: disconnect),
        ])
    }

    @Test func aScreenStillConnectedAtTheStopHasNoDisconnect() {
        let spec = VirtualScreenSpec(serialNumber: 102, sizes: [.init(width: 1280, height: 720)])
        let expectation = Scenario.virtualScreenExpectation([
            HappenedEvent(times: .init(asked: 1, done: 1.1), event: .connectScreen(spec), screenUUID: "V"),
        ])
        #expect(expectation.files.map(\.endedBy) == [nil])
        #expect(expectation.events.map(\.event) == ["screen connected"])
        #expect(spec.name == "MSR Test 102")
    }
}
