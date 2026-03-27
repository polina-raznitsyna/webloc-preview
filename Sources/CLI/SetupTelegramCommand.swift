import ArgumentParser
import Foundation
import Core

struct SetupTelegramCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup-telegram",
        abstract: "Configure Telegram API for better metadata fetching"
    )

    func run() throws {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".webloc-preview")
        let configPath = configDir.appendingPathComponent("tg_config.json")

        // Check if already configured
        if FileManager.default.fileExists(atPath: configPath.path) {
            print("Telegram is already configured.")
            print("To reconfigure, delete ~/.webloc-preview/tg_config.json and run again.")
            return
        }

        // Save api_id / api_hash
        print("=== Telegram API Setup ===")
        print("Get your credentials at https://my.telegram.org → API development tools\n")

        print("api_id: ", terminator: "")
        guard let apiIdStr = readLine()?.trimmingCharacters(in: .whitespaces),
              let apiId = Int(apiIdStr) else {
            print("Invalid api_id")
            throw ExitCode.failure
        }

        print("api_hash: ", terminator: "")
        guard let apiHash = readLine()?.trimmingCharacters(in: .whitespaces),
              !apiHash.isEmpty else {
            print("Invalid api_hash")
            throw ExitCode.failure
        }

        // Save config
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let config: [String: Any] = ["api_id": apiId, "api_hash": apiHash]
        let data = try JSONSerialization.data(withJSONObject: config)
        try data.write(to: configPath)
        print("Config saved.\n")

        // Check venv
        let venvPython = configDir.appendingPathComponent("venv/bin/python3").path
        if !FileManager.default.fileExists(atPath: venvPython) {
            print("Setting up Python environment...")
            let venv = Process()
            venv.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            venv.arguments = ["-m", "venv", configDir.appendingPathComponent("venv").path]
            try venv.run()
            venv.waitUntilExit()

            let pip = Process()
            pip.executableURL = URL(fileURLWithPath: configDir.appendingPathComponent("venv/bin/pip").path)
            pip.arguments = ["install", "telethon"]
            try pip.run()
            pip.waitUntilExit()
            print("Telethon installed.\n")
        }

        // Run interactive auth
        print("Now authenticating with Telegram...")
        print("You'll need to enter your phone number and a confirmation code.\n")

        let success = TelegramFetcher.runAuth()
        if success {
            print("\nTelegram integration ready!")
        } else {
            print("\nAuth failed. Try again with: webloc-preview setup-telegram")
            throw ExitCode.failure
        }
    }
}
