import ArgumentParser
import Foundation
import Core

struct CleanupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup",
        abstract: "Remove all webloc-preview traces from the system"
    )

    func run() throws {
        // 1. Remove all LaunchAgents
        try LaunchAgentManager.removeAll()
        print("Removed all LaunchAgents.")

        // 2. Remove log file
        let logFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/webloc-preview.log")
        if FileManager.default.fileExists(atPath: logFile.path) {
            try FileManager.default.removeItem(at: logFile)
            print("Removed log file.")
        }

        // 3. Scan for xattr marks
        print("Scanning for processed .webloc files to remove marks...")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let exclusionFilter = ExclusionFilter(customExclusions: [])
        let enumerator = FileManager.default.enumerator(at: home, includingPropertiesForKeys: nil)
        var count = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            if exclusionFilter.shouldExclude(fileURL.path) {
                enumerator?.skipDescendants()
                continue
            }
            if fileURL.pathExtension == "webloc" && ProcessingMarker.isProcessed(fileURL) {
                try? ProcessingMarker.removeMark(fileURL)
                count += 1
            }
        }
        print("Removed processing marks from \(count) files.")
        print("\nCleanup complete. The binary itself is not removed — delete it manually if needed.")
    }
}
