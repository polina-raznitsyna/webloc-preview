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

            var title: String? = nil
            var imageData: Data? = nil
            var faviconData: Data? = nil

            // 1. Telegram API
            if let tg = await TelegramFetcher.fetch(url: pageURL), !tg.title.isEmpty {
                title = tg.title
                imageData = tg.imageData
                print("  TG: title=\(tg.title), img=\(tg.imageData != nil)")
            }

            // 2. URL slug as last resort for title
            if title == nil || title!.hasPrefix("http") || title == pageURL.absoluteString {
                title = MetadataFetcher.titleFromURL(pageURL)
                print("  URL slug: \(title!)")
            }

            // 3. Screenshot if no image
            if imageData == nil {
                imageData = try? await ScreenshotService.shared.takeScreenshot(of: pageURL)
            }

            // 4. Google favicon
            if let gf = MetadataFetcher.googleFaviconURL(for: domain) {
                faviconData = await MetadataFetcher.downloadImage(url: gf)
            }

            // 5. Render and apply
            let cleanedTitle = MetadataFetcher.cleanTitle(title!)
            let card = try CardRenderer.render(domain: domain, imageData: imageData, faviconData: faviconData)
            _ = IconSetter.setIcon(card, for: fileURL)
            let newURL = try IconSetter.renameFile(at: fileURL, title: cleanedTitle)
            try ProcessingMarker.markProcessed(newURL)
            print("  -> \(newURL.lastPathComponent)")
            Logger.log("Processed: \(newURL.lastPathComponent)")

        } catch {
            Logger.error("Failed to process \(fileURL.path): \(error.localizedDescription)")
            print("  Error: \(error.localizedDescription)")
        }
    }
}
