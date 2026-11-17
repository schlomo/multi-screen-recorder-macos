import Foundation
import RecorderCore
import Synchronization
import Testing
@testable import msr

/// Where each kind of text of `msr record` goes, with and without `--quiet`, and when the status line is drawn.
@Suite struct RecordOutputTests {
    private final class Collected: Sendable {
        private let lines = Mutex<[String]>([])
        func add(_ text: String) { lines.withLock { $0.append(text) } }
        var all: [String] { lines.withLock { $0 } }
    }

    private func output(quiet: Bool, isTerminal: Bool = true) -> (RecordOutput, standardOutput: Collected, standardError: Collected) {
        let out = Collected()
        let err = Collected()
        let writer = StandardErrorWriter(isTerminal: isTerminal, width: { 80 }, sink: { err.add($0) })
        return (RecordOutput(quiet: quiet, standardOutput: { out.add($0) }, standardError: writer), out, err)
    }

    private func destination(_ kind: RecordOutput.Kind, quiet: Bool) -> RecordOutput.Destination {
        RecordOutput(quiet: quiet, standardOutput: { _ in }, standardError: .shared).destination(of: kind)
    }

    @Test func theFolderPathIsTheOnlyStandardOutputAndAlwaysThere() {
        for kind in RecordOutput.Kind.allCases {
            for quiet in [false, true] {
                #expect((destination(kind, quiet: quiet) == .standardOutput) == (kind == .recordingFolder), "\(kind) quiet \(quiet)")
            }
        }
    }

    @Test(arguments: [RecordOutput.Kind.banner, .whatWillBeRecorded, .readyCheckPassed, .recordingFolderNotice,
                      .stopMessage, .event, .problem, .summary, .summaryOfFailedRun, .readyCheckFailed, .error])
    func everythingForPeopleGoesToStandardErrorUnlessQuiet(kind: RecordOutput.Kind) {
        #expect(destination(kind, quiet: false) == .standardError)
    }

    @Test(arguments: [RecordOutput.Kind.readyCheckFailed, .problem, .summaryOfFailedRun, .error])
    func quietStillWritesFailuresAndProblems(kind: RecordOutput.Kind) {
        #expect(destination(kind, quiet: true) == .standardError)
    }

    @Test(arguments: [RecordOutput.Kind.banner, .whatWillBeRecorded, .readyCheckPassed, .recordingFolderNotice,
                      .stopMessage, .event, .summary])
    func quietWritesNothingElse(kind: RecordOutput.Kind) {
        #expect(destination(kind, quiet: true) == .nowhere)
    }

    @Test func theReadyCheckAndTheSummaryAreToldByTheirResult() {
        #expect(RecordOutput.Kind.readyCheck(isReady: true) == .readyCheckPassed)
        #expect(RecordOutput.Kind.readyCheck(isReady: false) == .readyCheckFailed)
        #expect(RecordOutput.Kind.summary(endedWithError: false) == .summary)
        #expect(RecordOutput.Kind.summary(endedWithError: true) == .summaryOfFailedRun)
    }

    @Test func theCommandsQuietFlagDecides() throws {
        for (arguments, quiet) in [(["record"], false), (["record", "--quiet"], true)] {
            let record = try #require(try CommandLineInterface.parseAsRoot(arguments) as? CommandLineInterface.Record)
            let err = Collected()
            let output = RecordOutput(
                record: record, standardOutput: { _ in }, standardError: StandardErrorWriter(isTerminal: false, width: { 80 }, sink: { err.add($0) }))
            output.say(.banner, "banner\n")
            #expect(err.all == (quiet ? [] : ["banner\n"]))
        }
    }

    @Test func sayDeliversToTheDestination() {
        for quiet in [false, true] {
            let (output, out, err) = output(quiet: quiet, isTerminal: false)
            output.say(.recordingFolder, "/folder")
            output.say(.banner, "banner\n")
            output.say(.error, "Error: x\n")
            #expect(out.all == ["/folder"])
            #expect(err.all == (quiet ? ["Error: x\n"] : ["banner\n", "Error: x\n"]))
        }
    }

    @Test func theStatusLineIsDrawnOnATerminalWhileRecordingAndNotQuiet() {
        let (output, _, err) = output(quiet: false)
        output.drawStatusLine(isStopping: false) { "one" }
        #expect(err.all == ["\rone\u{1B}[K"])
    }

    @Test func noStatusLineWhenQuietStoppingOrNotATerminal() {
        for (quiet, isTerminal, isStopping) in [(true, true, false), (false, true, true), (false, false, false)] {
            let (output, _, err) = output(quiet: quiet, isTerminal: isTerminal)
            output.drawStatusLine(isStopping: isStopping) { Issue.record("the text is built for nothing"); return "" }
            #expect(err.all.isEmpty)
        }
    }

    @Test func endingTheStatusLineClearsIt() {
        let (output, _, err) = output(quiet: false)
        output.drawStatusLine(isStopping: false) { "one" }
        output.endStatusLine()
        output.say(.summary, "summary\n")
        #expect(err.all == ["\rone\u{1B}[K", "\r\u{1B}[K", "summary\n"])
    }
}
