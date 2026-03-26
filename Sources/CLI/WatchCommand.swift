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
        dispatchMain()
    }

    private static func processDetectedFile(path: String, notify: Bool) async {
        let fileURL = URL(fileURLWithPath: path)

        guard !ProcessingMarker.isProcessed(fileURL) else { return }

        do {
            let pageURL = try WeblocFile.readURL(from: fileURL)
            let domain = WeblocFile.domain(from: pageURL)

            // 1: LinkPresentation (Apple Notes engine)
            MetadataFetcher._lastLPResult = nil
            var title: String? = nil
            var imageData: Data? = nil
            var faviconData: Data? = nil

            if let lpMeta = await MetadataFetcher.fetchViaLinkPresentation(url: pageURL) {
                let lpResult = MetadataFetcher._lastLPResult
                if !lpMeta.isAntiBot {
                    title = lpMeta.title
                    imageData = lpResult?.imageData
                    faviconData = lpResult?.iconData
                }
            }

            // 2: HTTP fallback
            if title == nil || title == pageURL.absoluteString {
                if let metadata = try? await MetadataFetcher.fetch(url: pageURL), !metadata.isAntiBot {
                    title = metadata.title
                    if imageData == nil, let imageURL = metadata.imageURL {
                        imageData = await MetadataFetcher.downloadImage(url: imageURL)
                    }
                    if faviconData == nil, let faviconURL = metadata.faviconURL {
                        faviconData = await MetadataFetcher.downloadImage(url: faviconURL)
                    }
                }
            }

            // 3: WebKit fallback
            if title == nil || title!.hasPrefix("http") {
                if let wk = try? await ScreenshotService.shared.fetchMetadataViaWebKit(url: pageURL),
                   !wk.isAntiBot, !wk.title.hasPrefix("http") {
                    title = wk.title
                }
            }

            // 4: URL slug
            if title == nil || title!.hasPrefix("http") {
                title = MetadataFetcher.titleFromURL(pageURL)
            }

            // 5: Screenshot fallback
            if imageData == nil {
                imageData = try? await ScreenshotService.shared.takeScreenshot(of: pageURL)
            }

            // 6: Google favicon
            if faviconData == nil, let gf = MetadataFetcher.googleFaviconURL(for: domain) {
                faviconData = await MetadataFetcher.downloadImage(url: gf)
            }

            let cleanedTitle = MetadataFetcher.cleanTitle(title!)
            let card = try CardRenderer.render(
                domain: domain, imageData: imageData, faviconData: faviconData
            )
            _ = IconSetter.setIcon(card, for: fileURL)
            let newURL = try IconSetter.renameFile(at: fileURL, title: cleanedTitle)
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
