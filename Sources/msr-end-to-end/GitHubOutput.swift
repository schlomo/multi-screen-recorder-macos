import EndToEndLogic
import Foundation

/// The run's report for GitHub Actions, only when the environment says the
/// run is there: annotations as workflow commands on standard output, and
/// the table appended to the job summary file the environment names.
struct GitHubOutput {
    let annotates: Bool
    let summaryFile: URL?

    init(environment: [String: String]) {
        annotates = environment["GITHUB_ACTIONS"] == "true"
        summaryFile = environment["GITHUB_STEP_SUMMARY"].flatMap { $0.isEmpty ? nil : URL(filePath: $0) }
    }

    func annotate(scenario: String, _ firstFailure: String) {
        guard annotates else { return }
        RunLog.out(GitHubReport.annotation(title: scenario, message: firstFailure))
    }

    func summarize(rows: [GitHubReport.Row], verdict: String) throws {
        guard let summaryFile else { return }
        let handle: FileHandle
        do {
            if !FileManager.default.fileExists(atPath: summaryFile.path) {
                FileManager.default.createFile(atPath: summaryFile.path, contents: nil)
            }
            handle = try FileHandle(forWritingTo: summaryFile)
        } catch {
            throw DriverError("cannot write the job summary \(summaryFile.path): \(error)")
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(GitHubReport.summary(rows: rows, verdict: verdict).utf8))
    }
}
