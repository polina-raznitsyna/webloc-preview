import Foundation

public struct TelegramPreview: Sendable {
    public let title: String
    public let description: String
    public let siteName: String
    public let imageData: Data?
}

public struct TelegramFetcher {
    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".webloc-preview")
    private static let venvPython = configDir.appendingPathComponent("venv/bin/python3").path
    private static let configFile = configDir.appendingPathComponent("tg_config.json").path

    /// Path to the Python helper script (in the package's scripts/ dir or next to the binary)
    private static var scriptPath: String {
        // Look relative to executable
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let candidates = [
            execURL.deletingLastPathComponent().appendingPathComponent("../scripts/tg_preview.py").path,
            execURL.deletingLastPathComponent().appendingPathComponent("tg_preview.py").path,
            configDir.appendingPathComponent("tg_preview.py").path,
        ]
        // Also check the source repo location
        let repoScript = execURL.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/tg_preview.py").path

        for path in candidates + [repoScript] {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        // Fallback: assume it's installed alongside the binary
        return configDir.appendingPathComponent("tg_preview.py").path
    }

    /// Check if Telegram integration is configured and authorized.
    public static var isConfigured: Bool {
        FileManager.default.fileExists(atPath: configFile)
    }

    /// Fetch metadata via Telegram's getWebPagePreview.
    /// Returns nil if Telegram is not configured or fetch fails.
    public static func fetch(url: URL) async -> TelegramPreview? {
        guard isConfigured else { return nil }

        guard let result = runScript(args: ["fetch", url.absoluteString]) else {
            return nil
        }

        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["error"] == nil else {
            return nil
        }

        let title = json["title"] as? String ?? ""
        let description = json["description"] as? String ?? ""
        let siteName = json["site_name"] as? String ?? ""

        guard !title.isEmpty else { return nil }

        // Load image if path provided
        var imageData: Data? = nil
        if let imagePath = json["image_path"] as? String {
            imageData = FileManager.default.contents(atPath: imagePath)
            // Clean up temp file
            try? FileManager.default.removeItem(atPath: imagePath)
        }

        return TelegramPreview(
            title: title,
            description: description,
            siteName: siteName,
            imageData: imageData
        )
    }

    /// Run the Python script with given arguments. Returns stdout as string.
    private static func runScript(args: [String]) -> String? {
        let python = FileManager.default.fileExists(atPath: venvPython)
            ? venvPython
            : "/usr/bin/python3"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [scriptPath] + args
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run interactive auth. Used by setup-telegram command.
    public static func runAuth() -> Bool {
        let python = FileManager.default.fileExists(atPath: venvPython)
            ? venvPython
            : "/usr/bin/python3"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [scriptPath, "auth"]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("Failed to run auth: \(error.localizedDescription)")
            return false
        }
    }
}
