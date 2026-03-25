import Foundation
import CryptoKit

public struct LaunchAgentManager {
    private static let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
    private static let prefix = "com.webloc-preview.watch"

    public static func register(
        paths: [String],
        excludes: [String],
        notify: Bool,
        executablePath: String
    ) throws {
        let hash = stableHash(paths)
        let label = "\(prefix).\(hash)"
        let plistURL = launchAgentsDir.appendingPathComponent("\(label).plist")

        var args = [executablePath, "watch"] + paths
        if !excludes.isEmpty {
            args += ["--exclude"] + excludes
        }
        if notify {
            args += ["--notify"]
        }
        args += ["--daemon"]

        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/webloc-preview.log").path

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": args,
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        // Ensure LaunchAgents directory exists
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        try data.write(to: plistURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistURL.path]
        try process.run()
        process.waitUntilExit()
    }

    public static func remove(paths: [String]) throws -> Bool {
        let hash = stableHash(paths)
        let label = "\(prefix).\(hash)"
        let plistURL = launchAgentsDir.appendingPathComponent("\(label).plist")

        guard FileManager.default.fileExists(atPath: plistURL.path) else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistURL.path]
        try process.run()
        process.waitUntilExit()

        try FileManager.default.removeItem(at: plistURL)
        return true
    }

    public static func removeAll() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: launchAgentsDir.path) else { return }
        let contents = try fm.contentsOfDirectory(at: launchAgentsDir, includingPropertiesForKeys: nil)
        for file in contents where file.lastPathComponent.hasPrefix(prefix) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", file.path]
            try process.run()
            process.waitUntilExit()
            try fm.removeItem(at: file)
        }
    }

    public static func listAll() throws -> [(label: String, paths: [String])] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: launchAgentsDir.path) else { return [] }
        let contents = try fm.contentsOfDirectory(at: launchAgentsDir, includingPropertiesForKeys: nil)
        var results: [(String, [String])] = []

        for file in contents where file.lastPathComponent.hasPrefix(prefix) {
            if let data = fm.contents(atPath: file.path),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let args = plist["ProgramArguments"] as? [String] {
                let label = plist["Label"] as? String ?? file.lastPathComponent
                let watchIdx = args.firstIndex(of: "watch").map { $0 + 1 } ?? 2
                let slice = Array(args[watchIdx...])
                let paths = slice.prefix(while: { !$0.hasPrefix("-") })
                let pathArray = Array(paths)
                results.append((label, pathArray.isEmpty ? ["~/"] : pathArray))
            }
        }
        return results
    }

    private static func stableHash(_ paths: [String]) -> String {
        let input = paths.sorted().joined(separator: "|")
        let data = Data(input.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
