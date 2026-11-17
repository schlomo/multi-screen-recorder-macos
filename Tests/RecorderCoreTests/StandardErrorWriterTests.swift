import Foundation
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
        writer.showStatus("Recording 0:00:01")
        writer.write("event\n")
        writer.showStatus("Recording 0:00:02")
        writer.endStatus()
        #expect(collected.all == ["event\n"])
    }

    @Test func aTerminalRedrawsTheLineFromItsStartAndErasesToItsEnd() {
        let (writer, collected) = writer(isTerminal: true)
        writer.showStatus("one")
        writer.showStatus("two")
        #expect(collected.all == ["\rone\u{1B}[K", "\rtwo\u{1B}[K"])
    }

    @Test func anEventLineBetweenTwoRedrawsClearsPrintsAndRedraws() {
        let (writer, collected) = writer(isTerminal: true)
        writer.showStatus("one")
        writer.write("event\n")
        writer.showStatus("two")
        #expect(collected.all == ["\rone\u{1B}[K", clear, "event\n", "\rone\u{1B}[K", "\rtwo\u{1B}[K"])
    }

    @Test func theEndClearsTheLineAndLaterWritesDoNotRedrawIt() {
        let (writer, collected) = writer(isTerminal: true)
        writer.showStatus("one")
        writer.endStatus()
        writer.write("summary\n")
        #expect(collected.all == ["\rone\u{1B}[K", clear, "summary\n"])
    }

    @Test func aWriteBeforeAnyStatusLineIsPlain() {
        let (writer, collected) = writer(isTerminal: true)
        writer.write("event\n")
        writer.endStatus()
        #expect(collected.all == ["event\n"])
    }

    @Test func aNarrowTerminalGetsTheLineCutToItsWidth() {
        let (writer, collected) = writer(isTerminal: true, width: 3)
        writer.showStatus("Recording")
        #expect(collected.all == ["\rRec\u{1B}[K"])
    }
}
