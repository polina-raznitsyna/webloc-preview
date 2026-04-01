import ArgumentParser
import Foundation
import Core

struct SetupTelegramCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup-telegram",
        abstract: "Authenticate with Telegram for metadata fetching"
    )

    func run() throws {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".webloc-preview")

        // Check if session already exists
        let sessionPath = configDir.appendingPathComponent("tg_session.session")
        if FileManager.default.fileExists(atPath: sessionPath.path) {
            print("Telegram is already set up.")
            print("To re-authenticate, delete ~/.webloc-preview/tg_session.session and run again.")
            return
        }

        // Ensure venv + telethon
        let venvPython = configDir.appendingPathComponent("venv/bin/python3").path
        if !FileManager.default.fileExists(atPath: venvPython) {
            print("Setting up Python environment...")
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            let venv = Process()
            venv.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            venv.arguments = ["-m", "venv", configDir.appendingPathComponent("venv").path]
            try venv.run()
            venv.waitUntilExit()

            let pip = Process()
            pip.executableURL = URL(fileURLWithPath: configDir.appendingPathComponent("venv/bin/pip").path)
            pip.arguments = ["install", "-q", "telethon"]
            try pip.run()
            pip.waitUntilExit()
            print("Done.\n")
        }

        // Copy script if needed
        let scriptDst = configDir.appendingPathComponent("tg_preview.py")
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let candidates = [
            execURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("scripts/tg_preview.py"),
        ]
        for src in candidates {
            if FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.removeItem(at: scriptDst)
                try? FileManager.default.copyItem(at: src, to: scriptDst)
                break
            }
        }

        // Run interactive auth
        print("=== Telegram Authentication ===")
        print("You'll enter your phone number and a code from Telegram.\n")

        let success = TelegramFetcher.runAuth()
        if success {
            print("\nReady! Telegram metadata will be used automatically.")
        } else {
            print("\nFailed. Try again: webloc-preview setup-telegram")
            throw ExitCode.failure
        }
    }
}
