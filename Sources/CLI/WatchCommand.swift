import ArgumentParser
import Foundation
import Core

struct WatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch for new .webloc files and process them"
    )

    @Argument(help: "Paths to watch (default: ~/)")
    var paths: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "Additional directories to exclude")
    var exclude: [String] = []

    @Flag(name: .long, help: "Show macOS notifications when files are processed")
    var notify = false

    @Flag(name: .long, help: "Run as daemon (internal, used by LaunchAgent)")
    var daemon = false

    func run() async throws {
        let resolvedPaths = paths.isEmpty
            ? [FileManager.default.homeDirectoryForCurrentUser.path]
            : paths.map { ($0 as NSString).expandingTildeInPath }

        if !daemon {
            let execPath = ProcessInfo.processInfo.arguments[0]
            try LaunchAgentManager.register(
                paths: resolvedPaths,
                excludes: exclude,
                notify: notify,
                executablePath: execPath
            )
            print("Watching: \(resolvedPaths.joined(separator: ", "))")
            print("LaunchAgent registered — will survive reboots.")
            print("Use 'webloc-preview stop' to stop watching.")
            return
        }

        Logger.log("Starting watch for: \(resolvedPaths.joined(separator: ", "))")

        // Serial queue: files processed one at a time
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)

        let watcher = FileWatcher(paths: resolvedPaths, exclusions: exclude) { path in
            continuation.yield(path)
        }
        watcher.start()

        for await path in stream {
            let shouldRetry = await Self.processDetectedFile(path: path, notify: notify)
            if shouldRetry {
                // Re-queue after a delay so Telegram rate limit can recover
                Task {
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                    continuation.yield(path)
                }
            }
        }
    }

    /// Returns true if file should be retried later (TG temporary failure).
    @discardableResult
    private static func processDetectedFile(path: String, notify: Bool) async -> Bool {
        let fileURL = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else { return false }
        guard !ProcessingMarker.isProcessed(fileURL) else { return false }

        do {
            let pageURL = try WeblocFile.readURL(from: fileURL)
            let domain = WeblocFile.domain(from: pageURL)

            var title: String? = nil
            var imageData: Data? = nil
            var faviconData: Data? = nil

            // 1: Telegram API
            let tgResult = TelegramFetcher.shared.fetch(url: pageURL)
            switch tgResult {
            case .success(let tg):
                title = MetadataFetcher.cleanTitle(tg.title)
                imageData = tg.imageData
            case .noPreview:
                break
            case .temporaryError:
                Logger.log("Deferred (TG rate limit): \(fileURL.lastPathComponent)")
                return true // retry later
            }

            // 2: HTTP fallback for title
            if title == nil {
                if let http = try? await MetadataFetcher.fetch(url: pageURL), !http.isAntiBot {
                    title = MetadataFetcher.cleanTitle(http.title)
                    if imageData == nil, let u = http.imageURL { imageData = await MetadataFetcher.downloadImage(url: u) }
                }
            }

            // 3: Screenshot if no image
            if imageData == nil {
                imageData = try? await ScreenshotService.shared.takeScreenshot(of: pageURL)
            }

            // 3: Google favicon
            if let gf = MetadataFetcher.googleFaviconURL(for: domain) {
                faviconData = await MetadataFetcher.downloadImage(url: gf)
            }

            let card = try CardRenderer.render(
                domain: domain, imageData: imageData, faviconData: faviconData
            )
            _ = IconSetter.setIcon(card, for: fileURL)
            let newURL = title != nil
                ? try IconSetter.renameFile(at: fileURL, title: title!)
                : fileURL
            try ProcessingMarker.markProcessed(newURL)

            Logger.log("Processed: \(newURL.lastPathComponent)")

            if notify {
                sendNotification(title: "webloc-preview", body: newURL.lastPathComponent)
            }
        } catch {
            Logger.error("Failed: \(path) — \(error.localizedDescription)")
        }
        return false
    }

    private static func sendNotification(title: String, body: String) {
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""]
        try? process.run()
    }
}
