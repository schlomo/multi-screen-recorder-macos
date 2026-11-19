import Foundation
import Testing
@testable import EndToEndLogic

@Suite struct RestoreTests {
    static let dell = MachineState.Screen(
        uuid: "A95C2BA6", active: true, x: 0, y: 0, width: 3440, height: 1440, pixelWidth: 6880, pixelHeight: 2880,
        refreshRate: 60, modeID: 40, rotation: 0, mirrorsUUID: nil)
    static let wacom = MachineState.Screen(
        uuid: "037036FB", active: true, x: 760, y: 1440, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160,
        refreshRate: 60, modeID: 43, rotation: 0, mirrorsUUID: nil)
    static let saved = MachineState(
        screens: [dell, wacom], mainScreenUUID: "A95C2BA6", defaultInputUID: "Razer", defaultOutputUID: "Pebble",
        loopbackDevices: [.init(uid: "BlackHole2ch_UID", sampleRate: 48_000, inputVolumes: [1, nil, nil])])

    /// The saved state with one screen changed; the state keeps its screens sorted by UUID.
    static func changing(_ uuid: String, _ change: (inout MachineState.Screen) -> Void) -> MachineState {
        var state = saved
        let index = state.screens.firstIndex { $0.uuid == uuid }!
        change(&state.screens[index])
        return state
    }

    @Test func anUnchangedMacNeedsNothing() {
        #expect(Self.saved.differences(to: Self.saved) == [])
        let plan = RestorePlan(saved: Self.saved, current: Self.saved)
        #expect(plan.actions == [])
        #expect(plan.forThePerson == [])
    }

    @Test func theScreensAreComparedByUUIDWhateverTheirOrder() {
        let reordered = MachineState(screens: [Self.wacom, Self.dell], mainScreenUUID: "A95C2BA6", defaultInputUID: "Razer",
                                     defaultOutputUID: "Pebble", loopbackDevices: Self.saved.loopbackDevices)
        #expect(Self.saved.differences(to: reordered) == [])
    }

    @Test func aMovedOrSwitchedScreenOrAnotherMainScreenIsArrangedAgain() {
        let moved = Self.changing("A95C2BA6") { $0.x = -1280 }
        #expect(RestorePlan(saved: Self.saved, current: moved).actions == [.arrangeScreens])
        #expect(Self.saved.differences(to: moved).count == 1)
        let mode = Self.changing("037036FB") { $0.modeID = 44 }
        #expect(RestorePlan(saved: Self.saved, current: mode).actions == [.arrangeScreens])
        var main = Self.saved
        main.mainScreenUUID = "037036FB"
        #expect(RestorePlan(saved: Self.saved, current: main).actions == [.arrangeScreens])
        #expect(Self.saved.differences(to: main) == ["the main screen is 037036FB, was A95C2BA6"])
    }

    @Test func theDefaultDevicesAndTheLoopbackDeviceArePutBack() {
        var changed = Self.saved
        changed.defaultInputUID = "BlackHole2ch_UID"
        changed.defaultOutputUID = nil
        changed.loopbackDevices[0].sampleRate = 44_100
        changed.loopbackDevices[0].inputVolumes[0] = 0.5
        let plan = RestorePlan(saved: Self.saved, current: changed)
        #expect(plan.actions == [
            .defaultInput(uid: "Razer"), .defaultOutput(uid: "Pebble"), .sampleRate(uid: "BlackHole2ch_UID", rate: 48_000),
            .inputVolume(uid: "BlackHole2ch_UID", element: 0, volume: 1),
        ])
        #expect(Self.saved.differences(to: changed).count == 3)
    }

    @Test func whatNoInterfaceCanPutBackIsLeftToThePerson() {
        var changed = Self.changing("A95C2BA6") { $0.rotation = 90 }
        changed.screens.removeAll { $0.uuid == "037036FB" }
        changed.loopbackDevices = []
        let plan = RestorePlan(saved: Self.saved, current: changed)
        #expect(plan.forThePerson == [
            "screen 037036FB is gone: connect it again",
            "screen A95C2BA6 is rotated 90.0°: set it to 0.0° in System Settings",
            "the loopback device BlackHole2ch_UID is gone",
        ])
        let off = Self.changing("037036FB") { $0.active = false }
        #expect(RestorePlan(saved: Self.saved, current: off).forThePerson == ["screen 037036FB is off: switch it on"])
        #expect(RestorePlan(saved: Self.saved, current: off).actions == [])
    }

    @Test func aNewScreenIsADifference() {
        var more = Self.saved
        more.screens.append(.init(uuid: "VIRTUAL", active: true, x: -1280, y: 0, width: 1280, height: 720, pixelWidth: 1280,
                                  pixelHeight: 720, refreshRate: 60, modeID: 4, rotation: 0, mirrorsUUID: nil))
        #expect(Self.saved.differences(to: more) == ["screen VIRTUAL is new"])
    }

    @Test func theRestoreFileKeepsTheStateAndTheProcesses() throws {
        let file = RestoreFile(saved: Self.saved, processes: [.init(pid: 123, executable: "/x/msr", stopSignal: 2)])
        #expect(try RestoreFile(json: file.jsonData()) == file)
        #expect(throws: (any Error).self) { try RestoreFile(json: Data("{}".utf8)) }
    }
}
