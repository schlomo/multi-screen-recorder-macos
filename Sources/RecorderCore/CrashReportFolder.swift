import Foundation
import RecorderLogic

/// The folder macOS writes crash reports to.
public func crashReportFolder(homeFolder: URL) -> URL {
    homeFolder.appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
}

/// The folder of the text copies of crash reports, next to the settings file.
public func crashReportTextCopyFolder(homeFolder: URL) -> URL {
    homeFolder.appending(path: "Library/Application Support/Multi Screen Recorder/Crash Reports", directoryHint: .isDirectory)
}

/// Copies the crash report `name` to `<base name>.txt` in the text copy
/// folder, replacing a copy of the same name, and returns the copy.
public func makeTextCopy(of name: String, homeFolder: URL) throws -> URL {
    let copyFolder = crashReportTextCopyFolder(homeFolder: homeFolder)
    try FileManager.default.createDirectory(at: copyFolder, withIntermediateDirectories: true)
    let copy = copyFolder.appending(path: CrashReport.textCopyName(crashReportName: name))
    if FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)) {
        try FileManager.default.removeItem(at: copy)
    }
    try FileManager.default.copyItem(at: crashReportFolder(homeFolder: homeFolder).appending(path: name), to: copy)
    return copy
}

/// The path of the program that crashed, from the crash report `name`.
public func crashReportProcPath(of name: String, homeFolder: URL) throws -> String {
    let report = crashReportFolder(homeFolder: homeFolder).appending(path: name)
    return try CrashReport.procPath(reportText: String(contentsOf: report, encoding: .utf8), reportName: name)
}

/// The names of the entries directly in the crash report folder. A missing
/// folder means no reports; a folder that exists but cannot be read is an error.
public func crashReportFileNames(homeFolder: URL) throws -> [String] {
    let folder = crashReportFolder(homeFolder: homeFolder)
    guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return [] }
    return try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
}
