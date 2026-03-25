import ArgumentParser
import Foundation
import Core

struct ProcessCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "process",
        abstract: "Process a .webloc file or folder"
    )

    @Argument(help: "Path to .webloc file or folder")
    var path: String

    @Flag(name: .long, help: "Reprocess already-processed files")
    var force = false

    func run() async throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            print("Error: path does not exist: \(path)")
            throw ExitCode.failure
        }

        if isDir.boolValue {
            let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil)
            while let fileURL = enumerator?.nextObject() as? URL {
                if fileURL.pathExtension == "webloc" {
                    await processFile(fileURL)
                }
            }
        } else {
            await processFile(url)
        }
    }

    private func processFile(_ fileURL: URL) async {
        do {
            if !force && ProcessingMarker.isProcessed(fileURL) {
                print("Skipping (already processed): \(fileURL.lastPathComponent)")
                return
            }

            let pageURL = try WeblocFile.readURL(from: fileURL)
            let domain = WeblocFile.domain(from: pageURL)
            print("Processing: \(fileURL.lastPathComponent) -> \(pageURL)")

            // Step 1: Try HTTP metadata fetch
            var metadata = try await MetadataFetcher.fetch(url: pageURL)
            var usedWebKit = false

            // Step 2: If anti-bot detected, retry via WebKit (renders JS, waits 8s)
            if metadata.isAntiBot {
                print("  Anti-bot detected, retrying with WebKit...")
                if let webkitMeta = try? await ScreenshotService.shared.fetchMetadataViaWebKit(url: pageURL),
                   !webkitMeta.isAntiBot {
                    metadata = webkitMeta
                    usedWebKit = true
                } else {
                    // WebKit also blocked — use URL slug as title, continue with screenshot
                    let urlTitle = MetadataFetcher.titleFromURL(pageURL)
                    print("  Anti-bot persists. Using URL title: \(urlTitle)")
                    metadata = PageMetadata(title: urlTitle, imageURL: nil, faviconURL: nil)
                }
            }

            // Step 2b: If title looks like a raw URL, extract from slug
            if metadata.title.hasPrefix("http") {
                let urlTitle = MetadataFetcher.titleFromURL(pageURL)
                metadata = PageMetadata(title: urlTitle, imageURL: metadata.imageURL, faviconURL: metadata.faviconURL)
            }

            // Step 3: Get preview image (OG image → screenshot)
            var imageData: Data? = nil
            if let imageURL = metadata.imageURL {
                imageData = await MetadataFetcher.downloadImage(url: imageURL)
            }
            if imageData == nil {
                imageData = try? await ScreenshotService.shared.takeScreenshot(of: pageURL)
            }

            // Step 4: Get favicon (from page → Google favicon service)
            var faviconData: Data? = nil
            if let faviconURL = metadata.faviconURL {
                faviconData = await MetadataFetcher.downloadImage(url: faviconURL)
            }
            if faviconData == nil, let googleFav = MetadataFetcher.googleFaviconURL(for: domain) {
                faviconData = await MetadataFetcher.downloadImage(url: googleFav)
            }

            // Step 5: Render card and apply
            let card = try CardRenderer.render(
                domain: domain,
                imageData: imageData,
                faviconData: faviconData
            )

            let iconSet = IconSetter.setIcon(card, for: fileURL)
            if !iconSet {
                Logger.error("Failed to set icon for \(fileURL.path)")
            }

            let newURL = try IconSetter.renameFile(at: fileURL, title: metadata.title)
            print("  -> \(newURL.lastPathComponent)")

            try ProcessingMarker.markProcessed(newURL)
            Logger.log("Processed: \(newURL.lastPathComponent)")

        } catch {
            Logger.error("Failed to process \(fileURL.path): \(error.localizedDescription)")
            print("  Error: \(error.localizedDescription)")
        }
    }
}
