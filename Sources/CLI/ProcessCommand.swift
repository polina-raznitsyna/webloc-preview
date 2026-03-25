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

            // Step 1: Try Apple LinkPresentation (same engine as Apple Notes)
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
                    print("  LP: title=\(title ?? "nil"), image=\(imageData != nil), icon=\(faviconData != nil)")
                } else {
                    print("  LP returned anti-bot page")
                }
            }

            // Step 2: If LP didn't get a title, try HTTP + SwiftSoup
            if title == nil || title == pageURL.absoluteString {
                let metadata = try await MetadataFetcher.fetch(url: pageURL)
                if !metadata.isAntiBot {
                    title = metadata.title
                    if imageData == nil, let imageURL = metadata.imageURL {
                        imageData = await MetadataFetcher.downloadImage(url: imageURL)
                    }
                    if faviconData == nil, let faviconURL = metadata.faviconURL {
                        faviconData = await MetadataFetcher.downloadImage(url: faviconURL)
                    }
                }
            }

            // Step 3: If still no title, try WebKit
            if title == nil || title!.hasPrefix("http") {
                print("  Trying WebKit...")
                if let webkitMeta = try? await ScreenshotService.shared.fetchMetadataViaWebKit(url: pageURL),
                   !webkitMeta.isAntiBot,
                   !webkitMeta.title.hasPrefix("http") {
                    title = webkitMeta.title
                }
            }

            // Step 4: Last resort — extract title from URL slug
            if title == nil || title!.hasPrefix("http") {
                title = MetadataFetcher.titleFromURL(pageURL)
                print("  Using URL slug title: \(title!)")
            }

            // Step 5: Get preview image if still missing (screenshot)
            if imageData == nil {
                imageData = try? await ScreenshotService.shared.takeScreenshot(of: pageURL)
            }

            // Step 6: Get favicon if still missing (Google service)
            if faviconData == nil, let googleFav = MetadataFetcher.googleFaviconURL(for: domain) {
                faviconData = await MetadataFetcher.downloadImage(url: googleFav)
            }

            // Step 7: Render card and apply
            let card = try CardRenderer.render(
                domain: domain,
                imageData: imageData,
                faviconData: faviconData
            )

            let iconSet = IconSetter.setIcon(card, for: fileURL)
            if !iconSet {
                Logger.error("Failed to set icon for \(fileURL.path)")
            }

            let newURL = try IconSetter.renameFile(at: fileURL, title: title!)
            print("  -> \(newURL.lastPathComponent)")

            try ProcessingMarker.markProcessed(newURL)
            Logger.log("Processed: \(newURL.lastPathComponent)")

        } catch {
            Logger.error("Failed to process \(fileURL.path): \(error.localizedDescription)")
            print("  Error: \(error.localizedDescription)")
        }
    }
}
