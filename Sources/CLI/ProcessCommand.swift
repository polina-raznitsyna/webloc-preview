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

    /// Detect when LP returned a generic homepage title for a deep URL.
    /// e.g. WB returns "Интернет-магазин Wildberries..." for /catalog/564575849/detail.aspx
    private func isGenericTitle(_ title: String?, for url: URL) -> Bool {
        guard let title = title else { return false }
        // Only applies to URLs with a meaningful path (not homepage)
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return false }
        // If domain name (or its common part) appears in the title, it's likely a homepage title
        let domain = (url.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        let domainBase = domain.split(separator: ".").first.map(String.init) ?? domain
        let titleLower = title.lowercased()
        return titleLower.contains(domainBase) && titleLower.contains("магазин")
            || titleLower.contains("checking")
            || titleLower.contains("just a moment")
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

            // 1. LinkPresentation (Apple Notes engine)
            MetadataFetcher._lastLPResult = nil
            if let lp = await MetadataFetcher.fetchViaLinkPresentation(url: pageURL), !lp.isAntiBot {
                title = lp.title
                imageData = MetadataFetcher._lastLPResult?.imageData
                faviconData = MetadataFetcher._lastLPResult?.iconData
                print("  LP: title=\(title ?? "nil"), img=\(imageData != nil), icon=\(faviconData != nil)")
            }

            // 2. Telegram API (fast, handles anti-bot sites)
            if title == nil || title == pageURL.absoluteString || isGenericTitle(title, for: pageURL) {
                if let tg = await TelegramFetcher.fetch(url: pageURL) {
                    if !tg.title.isEmpty {
                        title = tg.title
                    }
                    if imageData == nil, let img = tg.imageData {
                        imageData = img
                    }
                    print("  TG: title=\(tg.title), img=\(tg.imageData != nil)")
                }
            }

            // 3. HTTP + SwiftSoup (non-throwing)
            if title == nil || title == pageURL.absoluteString {
                if let http = try? await MetadataFetcher.fetch(url: pageURL), !http.isAntiBot {
                    title = http.title
                    if imageData == nil, let u = http.imageURL { imageData = await MetadataFetcher.downloadImage(url: u) }
                    if faviconData == nil, let u = http.faviconURL { faviconData = await MetadataFetcher.downloadImage(url: u) }
                }
            }

            // 5. WebKit with polling (waits for JS challenges to resolve, up to 22s)
            if title == nil || title!.hasPrefix("http") || title == pageURL.absoluteString {
                print("  Trying WebKit (polling)...")
                if let wk = try? await ScreenshotService.shared.fetchMetadataViaWebKit(url: pageURL),
                   !wk.isAntiBot, !wk.title.hasPrefix("http"), wk.title != pageURL.absoluteString {
                    title = wk.title
                    if imageData == nil, let u = wk.imageURL { imageData = await MetadataFetcher.downloadImage(url: u) }
                    if faviconData == nil, let u = wk.faviconURL { faviconData = await MetadataFetcher.downloadImage(url: u) }
                    print("  WebKit: title=\(title ?? "nil")")
                }
            }

            // 6. URL slug as last resort for title
            if title == nil || title!.hasPrefix("http") || title == pageURL.absoluteString {
                title = MetadataFetcher.titleFromURL(pageURL)
                print("  URL slug: \(title!)")
            }

            // 7. Screenshot if no image
            if imageData == nil {
                imageData = try? await ScreenshotService.shared.takeScreenshot(of: pageURL)
            }

            // 8. Google favicon fallback
            if faviconData == nil, let gf = MetadataFetcher.googleFaviconURL(for: domain) {
                faviconData = await MetadataFetcher.downloadImage(url: gf)
            }

            // 9. Render and apply
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
