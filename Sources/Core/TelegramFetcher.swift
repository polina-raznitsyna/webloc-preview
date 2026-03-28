import Foundation

public struct TelegramPreview: Sendable {
    public let title: String
    public let description: String
    public let siteName: String
    public let imageData: Data?
}

/// Result of a Telegram fetch attempt.
public enum TelegramFetchResult: Sendable {
    /// Got metadata from Telegram
    case success(TelegramPreview)
    /// Telegram genuinely has no preview for this URL
    case noPreview
    /// Temporary failure (rate limit, connection issue) — should retry later
    case temporaryError
}

/// Manages a long-running Python daemon that keeps a persistent Telegram connection.
/// Telethon handles FloodWait automatically (up to 2 min).
public final class TelegramFetcher: @unchecked Sendable {
    public static let shared = TelegramFetcher()

    private var process: Process?
    private var toStdin: FileHandle?
    private var fromStdout: FileHandle?
    private let lock = NSLock()
    private var ready = false

    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".webloc-preview")
    private static let venvPython = configDir.appendingPathComponent("venv/bin/python3").path
    private static let scriptPath = configDir.appendingPathComponent("tg_preview.py").path
    private static let configFile = configDir.appendingPathComponent("tg_config.json").path

    /// Check if Telegram integration is configured.
    public static var isConfigured: Bool {
        FileManager.default.fileExists(atPath: configFile)
    }

    /// Fetch metadata via Telegram. Retries on rate limits.
    public func fetch(url: URL, maxRetries: Int = 3) -> TelegramFetchResult {
        guard Self.isConfigured else { return .noPreview }

        lock.lock()
        defer { lock.unlock() }

        for attempt in 0..<maxRetries {
            guard ensureRunning() else { return .temporaryError }

            // Send URL to daemon
            let line = url.absoluteString + "\n"
            guard let data = line.data(using: .utf8) else { return .temporaryError }
            toStdin?.write(data)

            // Read response
            guard let response = readLine(),
                  let jsonData = response.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                // Daemon crashed — restart and retry
                stop()
                continue
            }

            // Check for errors
            if let error = json["error"] as? String {
                if error == "flood_wait" {
                    // Telethon couldn't auto-handle (> 2 min wait)
                    let seconds = json["seconds"] as? Int ?? 30
                    if attempt < maxRetries - 1 {
                        Thread.sleep(forTimeInterval: Double(seconds) + 1)
                        continue
                    }
                    return .temporaryError
                }
                if error == "no_preview" {
                    return .noPreview
                }
                // Other error — might be temporary
                return .temporaryError
            }

            // Parse success
            let title = json["title"] as? String ?? ""
            guard !title.isEmpty else { return .noPreview }

            var imageData: Data? = nil
            if let imagePath = json["image_path"] as? String {
                imageData = FileManager.default.contents(atPath: imagePath)
                try? FileManager.default.removeItem(atPath: imagePath)
            }

            return .success(TelegramPreview(
                title: title,
                description: json["description"] as? String ?? "",
                siteName: json["site_name"] as? String ?? "",
                imageData: imageData
            ))
        }

        return .temporaryError
    }

    /// Run interactive auth. Used by setup-telegram command.
    public static func runAuth() -> Bool {
        let python = FileManager.default.fileExists(atPath: venvPython) ? venvPython : "/usr/bin/python3"
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

    // MARK: - Daemon lifecycle

    private func ensureRunning() -> Bool {
        if let p = process, p.isRunning, ready { return true }
        stop()
        return start()
    }

    private func start() -> Bool {
        let python = FileManager.default.fileExists(atPath: Self.venvPython)
            ? Self.venvPython : "/usr/bin/python3"
        guard FileManager.default.fileExists(atPath: Self.scriptPath) else { return false }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = [Self.scriptPath, "daemon"]
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return false
        }

        self.process = proc
        self.toStdin = stdinPipe.fileHandleForWriting
        self.fromStdout = stdoutPipe.fileHandleForReading

        // Wait for "ready" signal (daemon connected to Telegram)
        guard let line = readLine(),
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "ready" else {
            stop()
            return false
        }

        self.ready = true
        return true
    }

    private func stop() {
        process?.terminate()
        process = nil
        toStdin = nil
        fromStdout = nil
        ready = false
    }

    private func readLine() -> String? {
        guard let handle = fromStdout else { return nil }
        var data = Data()
        while true {
            let byte = handle.readData(ofLength: 1)
            if byte.isEmpty { return nil } // EOF / daemon crashed
            if byte[0] == UInt8(ascii: "\n") { break }
            data.append(byte)
        }
        return String(data: data, encoding: .utf8)
    }
}
