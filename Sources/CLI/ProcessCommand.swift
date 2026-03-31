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

            // 1. Telegram API (retry up to 3 times on temporary errors)
            for attempt in 1...3 {
                let tgResult = TelegramFetcher.shared.fetch(url: pageURL)
                switch tgResult {
                case .success(let tg):
                    title = MetadataFetcher.cleanTitle(tg.title)
                    imageData = tg.imageData
                    print("  TG: title=\(title!), img=\(tg.imageData != nil)")
                case .noPreview:
                    print("  TG: no preview available")
                case .temporaryError:
                    if attempt < 3 {
                        print("  TG: temporary error, retrying in 10s... (\(attempt)/3)")
                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                        continue
                    }
                    print("  TG: temporary error after 3 attempts, skipping")
                }
                break
            }

            // 2. Screenshot if no image
            if imageData == nil {
                imageData = try? await ScreenshotService.shared.takeScreenshot(of: pageURL)
            }

            // 3. Google favicon
            if let gf = MetadataFetcher.googleFaviconURL(for: domain) {
                faviconData = await MetadataFetcher.downloadImage(url: gf)
            }

            // 4. Render and apply (only rename if we got a title)
            let card = try CardRenderer.render(domain: domain, imageData: imageData, faviconData: faviconData)
            _ = IconSetter.setIcon(card, for: fileURL)
            let newURL = title != nil
                ? try IconSetter.renameFile(at: fileURL, title: title!)
                : fileURL
            try ProcessingMarker.markProcessed(newURL)
            print("  -> \(newURL.lastPathComponent)")
            Logger.log("Processed: \(newURL.lastPathComponent)")

        } catch {
            Logger.error("Failed to process \(fileURL.path): \(error.localizedDescription)")
            print("  Error: \(error.localizedDescription)")
        }
    }
}
