import ArgumentParser
import Foundation
import Core

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show current watch status and statistics"
    )

    func run() throws {
        let agents = try LaunchAgentManager.listAll()

        if agents.isEmpty {
            print("No active watches.")
            return
        }

        print("Active watches:")
        for (_, paths) in agents {
            print("  \(paths.joined(separator: ", "))")
        }

        let logFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/webloc-preview.log")
        if let logContent = try? String(contentsOf: logFile, encoding: .utf8) {
            let lines = logContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let recent = lines.suffix(5)
            if !recent.isEmpty {
                print("\nRecent activity:")
                for line in recent {
                    print("  \(line)")
                }
            }
        }
    }
}
