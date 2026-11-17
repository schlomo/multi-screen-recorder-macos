import Foundation
import Darwin
import Synchronization
import Testing
@testable import RecorderCore

/// Everything `msr record` writes for people goes through one writer, so nothing prints into the middle of the status line.
@Suite struct StandardErrorWriterTests {
    private final class Collected: Sendable {
        private let writes = Mutex<[String]>([])
        func add(_ text: String) { writes.withLock { $0.append(text) } }
        var all: [String] { writes.withLock { $0 } }
    }

    private let clear = "\r\u{1B}[K"

    private func writer(isTerminal: Bool, width: Int? = 80) -> (StandardErrorWriter, Collected) {
        let collected = Collected()
        return (StandardErrorWriter(isTerminal: isTerminal, width: { width }, sink: { collected.add($0) }), collected)
    }

    @Test func notATerminalWritesNoStatusLineAndNoEscapeCode() {
        let (writer, collected) = writer(isTerminal: false)
        writer.showStatusLine("Recording 0:00:01")
        writer.write("event\n")
        writer.showStatusLine("Recording 0:00:02")
        writer.endStatusLine()
        #expect(collected.all == ["event\n"])
    }

    @Test func aTerminalRedrawsTheLineFromItsStartAndErasesToItsEnd() {
        let (writer, collected) = writer(isTerminal: true)
        writer.showStatusLine("one")
        writer.showStatusLine("two")
        #expect(collected.all == ["\rone\u{1B}[K", "\rtwo\u{1B}[K"])
    }

    @Test func anEventLineBetweenTwoRedrawsClearsPrintsAndRedraws() {
        let (writer, collected) = writer(isTerminal: true)
        writer.showStatusLine("one")
        writer.write("event\n")
        writer.showStatusLine("two")
        #expect(collected.all == ["\rone\u{1B}[K", clear + "event\n" + "\rone\u{1B}[K", "\rtwo\u{1B}[K"])
    }

    @Test func theEndClearsTheLineAndLaterWritesDoNotRedrawIt() {
        let (writer, collected) = writer(isTerminal: true)
        writer.showStatusLine("one")
        writer.endStatusLine()
        writer.write("summary\n")
        #expect(collected.all == ["\rone\u{1B}[K", clear, "summary\n"])
    }

    @Test func aWriteBeforeAnyStatusLineIsPlain() {
        let (writer, collected) = writer(isTerminal: true)
        writer.write("event\n")
        writer.endStatusLine()
        #expect(collected.all == ["event\n"])
    }

    @Test func aNarrowTerminalGetsTheLineCutToItsWidthMinusOne() {
        let (writer, collected) = writer(isTerminal: true, width: 4)
        writer.showStatusLine("Recording")
        #expect(collected.all == ["\rRec\u{1B}[K"])
    }

    // The process's own writer, on a pseudo-terminal, a pipe and a closed descriptor.

    private func pseudoTerminal(columns: UInt16 = 0) throws -> (master: Int32, slave: Int32) {
        var master: Int32 = 0
        var slave: Int32 = 0
        var size = winsize(ws_row: 24, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        try #require(openpty(&master, &slave, nil, nil, &size) == 0)
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        return (master, slave)
    }

    private func read(_ descriptor: Int32) -> String {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        return String(decoding: buffer.prefix(max(count, 0)), as: UTF8.self)
    }

    @Test func onATerminalTheDescriptorGetsTheStatusLineCutTo79WhenItsWidthIsUnknown() throws {
        let (master, slave) = try pseudoTerminal()
        defer { close(master); close(slave) }
        let writer = StandardErrorWriter(descriptor: slave, term: "xterm-256color")
        writer.showStatusLine(String(repeating: "x", count: 200))
        #expect(read(master) == "\r" + String(repeating: "x", count: 79) + "\u{1B}[K")
    }

    @Test func onATerminalTheDescriptorsWidthCutsTheLine() throws {
        let (master, slave) = try pseudoTerminal(columns: 10)
        defer { close(master); close(slave) }
        let writer = StandardErrorWriter(descriptor: slave, term: "xterm")
        writer.showStatusLine(String(repeating: "x", count: 200))
        #expect(read(master) == "\r" + String(repeating: "x", count: 9) + "\u{1B}[K")
    }

    @Test(arguments: [nil, "dumb", ""] as [String?])
    func aTerminalWithoutEscapeCodesGetsNoStatusLine(term: String?) throws {
        let (master, slave) = try pseudoTerminal()
        defer { close(master); close(slave) }
        let writer = StandardErrorWriter(descriptor: slave, term: term)
        writer.showStatusLine("one")
        writer.write("event\n")
        #expect(read(master) == "event\r\n") // the terminal's own newline translation
    }

    @Test func aPipeGetsPlainTextOnly() throws {
        var ends: [Int32] = [0, 0]
        try #require(pipe(&ends) == 0)
        defer { close(ends[0]); close(ends[1]) }
        let writer = StandardErrorWriter(descriptor: ends[1], term: "xterm")
        writer.showStatusLine("one")
        writer.write("event\n")
        writer.endStatusLine()
        _ = fcntl(ends[0], F_SETFL, O_NONBLOCK)
        #expect(read(ends[0]) == "event\n")
    }

    @Test func aFailedWriteDoesNotEndTheProcess() throws {
        var ends: [Int32] = [0, 0]
        try #require(pipe(&ends) == 0)
        close(ends[0])
        close(ends[1])
        let writer = StandardErrorWriter(descriptor: ends[1], term: nil)
        writer.write("nowhere to go\n")
    }
}
