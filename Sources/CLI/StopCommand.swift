import ArgumentParser
import Foundation
import Core

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop watching for .webloc files"
    )

    @Argument(help: "Paths to stop watching (default: stop all)")
    var paths: [String] = []

    func run() throws {
        if paths.isEmpty {
            try LaunchAgentManager.removeAll()
            print("All watches stopped and LaunchAgents removed.")
        } else {
            let resolvedPaths = paths.map { ($0 as NSString).expandingTildeInPath }
            let removed = try LaunchAgentManager.remove(paths: resolvedPaths)
            if removed {
                print("Stopped watching: \(resolvedPaths.joined(separator: ", "))")
            } else {
                print("No watch found for: \(resolvedPaths.joined(separator: ", "))")
            }
        }
    }
}
