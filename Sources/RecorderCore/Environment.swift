import Foundation
import RecorderLogic

public struct MissingHomeFolderError: Error, CustomStringConvertible {
    public var description: String { "HOME is not set, so the settings file cannot be found" }
}

/// The home folder from `HOME`, so the settings file follows the environment.
public func homeFolder() throws -> URL {
    guard let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty else {
        throw MissingHomeFolderError()
    }
    return URL(filePath: home, directoryHint: .isDirectory)
}

/// The version of the running build, from its bundle's Info.plist.
public var runningVersion: AppVersion {
    AppVersion(infoDictionary: Bundle.main.infoDictionary)
}
