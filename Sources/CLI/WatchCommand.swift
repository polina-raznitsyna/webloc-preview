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

        let watcher = FileWatcher(paths: resolvedPaths, exclusions: exclude) { path in
            Task {
                await Self.processDetectedFile(path: path, notify: notify)
            }
        }
        watcher.start()

        // Block forever — keep the daemon running
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            // Never resumes — daemon runs until killed
        }
    }

    private static func processDetectedFile(path: String, notify: Bool) async {
        let fileURL = URL(fileURLWithPath: path)

        guard !ProcessingMarker.isProcessed(fileURL) else { return }

        do {
            let pageURL = try WeblocFile.readURL(from: fileURL)
            let domain = WeblocFile.domain(from: pageURL)

            var metadata = try await MetadataFetcher.fetch(url: pageURL)
            if metadata.isAntiBot {
                if let webkitMeta = try? await ScreenshotService.shared.fetchMetadataViaWebKit(url: pageURL),
                   !webkitMeta.isAntiBot {
                    metadata = webkitMeta
                } else {
                    let urlTitle = MetadataFetcher.titleFromURL(pageURL)
                    metadata = PageMetadata(title: urlTitle, imageURL: nil, faviconURL: nil)
                }
            }
            if metadata.title.hasPrefix("http") {
                let urlTitle = MetadataFetcher.titleFromURL(pageURL)
                metadata = PageMetadata(title: urlTitle, imageURL: metadata.imageURL, faviconURL: metadata.faviconURL)
            }

            var imageData: Data? = nil
            if let imageURL = metadata.imageURL {
                imageData = await MetadataFetcher.downloadImage(url: imageURL)
            }
            if imageData == nil {
                imageData = try? await ScreenshotService.shared.takeScreenshot(of: pageURL)
            }

            var faviconData: Data? = nil
            if let faviconURL = metadata.faviconURL {
                faviconData = await MetadataFetcher.downloadImage(url: faviconURL)
            }
            if faviconData == nil, let googleFav = MetadataFetcher.googleFaviconURL(for: domain) {
                faviconData = await MetadataFetcher.downloadImage(url: googleFav)
            }

            let card = try CardRenderer.render(
                domain: domain, imageData: imageData, faviconData: faviconData
            )
            _ = IconSetter.setIcon(card, for: fileURL)
            let newURL = try IconSetter.renameFile(at: fileURL, title: metadata.title)
            try ProcessingMarker.markProcessed(newURL)

            Logger.log("Processed: \(newURL.lastPathComponent)")

            if notify {
                sendNotification(title: "webloc-preview", body: newURL.lastPathComponent)
            }
        } catch {
            Logger.error("Failed: \(path) — \(error.localizedDescription)")
        }
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
