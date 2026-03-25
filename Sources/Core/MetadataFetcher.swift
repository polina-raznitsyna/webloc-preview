import Foundation
import LinkPresentation
import SwiftSoup

public struct PageMetadata: Sendable {
    public let title: String
    public let imageURL: URL?
    public let faviconURL: URL?
    /// Raw HTML title (before OG override) for anti-bot detection
    public let rawHTMLTitle: String?

    public init(title: String, imageURL: URL?, faviconURL: URL?, rawHTMLTitle: String? = nil) {
        self.title = title
        self.imageURL = imageURL
        self.faviconURL = faviconURL
        self.rawHTMLTitle = rawHTMLTitle
    }

    /// Whether this metadata looks like an anti-bot/captcha page
    public var isAntiBot: Bool {
        let markers = ["captcha", "anti-bot", "antibot", "challenge", "не робот",
                       "robot", "verify you", "access denied", "just a moment",
                       "cloudflare", "ddos protection", "security check",
                       "blocked", "forbidden"]
        let textsToCheck = [title, rawHTMLTitle ?? ""]
        return textsToCheck.contains(where: { text in
            let lowered = text.lowercased()
            return markers.contains(where: { lowered.contains($0) })
        })
    }
}

public struct MetadataFetcher {
    /// Parse HTML string and extract OG metadata with fallbacks.
    public static func parseHTML(_ html: String, pageURL: URL) throws -> PageMetadata {
        let doc = try SwiftSoup.parse(html)

        // Title: og:title -> <title> -> URL
        let ogTitle = try doc.select("meta[property=og:title]").first()?.attr("content")
        let htmlTitle = try doc.title()
        let title = ogTitle?.nilIfEmpty ?? htmlTitle.nilIfEmpty ?? pageURL.absoluteString

        // Image: og:image
        let ogImage = try doc.select("meta[property=og:image]").first()?.attr("content")
        let imageURL = ogImage.flatMap { resolveURL($0, base: pageURL) }

        // Favicon: link[rel~=icon], prefer larger sizes
        let faviconHref = try bestFavicon(doc: doc)
        let faviconURL = faviconHref.flatMap { resolveURL($0, base: pageURL) }

        return PageMetadata(title: title, imageURL: imageURL, faviconURL: faviconURL, rawHTMLTitle: htmlTitle)
    }

    /// Fetch metadata via HTTP. Returns nil-equivalent metadata if anti-bot detected.
    public static func fetch(url: URL) async throws -> PageMetadata {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("ru-RU,ru;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? ""
        return try parseHTML(html, pageURL: url)
    }

    /// Download image data from URL. Returns nil on failure.
    public static func downloadImage(url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        return try? await URLSession.shared.data(for: request).0
    }

    /// Fetch metadata via Apple's LinkPresentation framework (same as Apple Notes).
    /// This is the most reliable method — handles anti-bot, JS rendering, etc.
    public static func fetchViaLinkPresentation(url: URL) async -> PageMetadata? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let provider = LPMetadataProvider()
                provider.timeout = 15
                provider.startFetchingMetadata(for: url) { metadata, error in
                    guard let metadata = metadata, error == nil else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let title = metadata.title

                    // Extract image
                    var imageData: Data? = nil
                    if let imageProvider = metadata.imageProvider {
                        let semaphore = DispatchSemaphore(value: 0)
                        imageProvider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                            imageData = data
                            semaphore.signal()
                        }
                        semaphore.wait()
                    }

                    // Extract favicon/icon
                    var iconData: Data? = nil
                    if let iconProvider = metadata.iconProvider {
                        let semaphore = DispatchSemaphore(value: 0)
                        iconProvider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                            iconData = data
                            semaphore.signal()
                        }
                        semaphore.wait()
                    }

                    let result = LPResult(
                        title: title,
                        imageData: imageData,
                        iconData: iconData
                    )
                    let pageMeta = PageMetadata(
                        title: title ?? url.absoluteString,
                        imageURL: nil,
                        faviconURL: nil
                    )
                    // Store the raw data for the caller to use
                    _lastLPResult = result
                    continuation.resume(returning: pageMeta)
                }
            }
        }
    }

    /// Holds image/icon data from the last LPMetadataProvider fetch
    /// (since LP provides raw data, not URLs)
    public nonisolated(unsafe) static var _lastLPResult: LPResult?

    /// Google favicon service as a reliable fallback.
    public static func googleFaviconURL(for domain: String) -> URL? {
        URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=64")
    }

    // MARK: - Private

    /// Pick the best (largest) favicon from link[rel~=icon] elements
    private static func bestFavicon(doc: Document) throws -> String? {
        let icons = try doc.select("link[rel~=icon]")
        var bestHref: String?
        var bestSize = 0

        for icon in icons {
            let href = try icon.attr("href")
            if href.isEmpty { continue }

            let sizes = try icon.attr("sizes") // e.g. "32x32", "192x192"
            let size = sizes.split(separator: "x").first.flatMap { Int($0) } ?? 0

            if size > bestSize || bestHref == nil {
                bestHref = href
                bestSize = size
            }
        }
        return bestHref
    }

    /// Extract a human-readable title from the URL path slug.
    /// e.g. "morning-coffee-irlandskiy-krem-arabika-1-kg" → "Morning Coffee Irlandskiy Krem Arabika 1 Kg"
    public static func titleFromURL(_ url: URL) -> String {
        // Take the last meaningful path component (skip IDs, query params)
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        // Find the longest slug-like component (contains hyphens, looks like a title)
        let bestSlug = pathComponents
            .filter { $0.contains("-") && $0.count > 10 }
            .max(by: { $0.count < $1.count })
            ?? pathComponents.last
            ?? url.host
            ?? url.absoluteString

        // Clean up: remove trailing IDs (numeric suffixes)
        let cleaned = bestSlug
            .replacingOccurrences(of: "-\\d+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        // Capitalize words
        return cleaned.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func resolveURL(_ string: String, base: URL) -> URL? {
        if let absolute = URL(string: string), absolute.scheme != nil {
            return absolute
        }
        return URL(string: string, relativeTo: base)?.absoluteURL
    }
}

/// Data extracted from LPMetadataProvider (provides raw image data, not URLs)
public struct LPResult: Sendable {
    public let title: String?
    public let imageData: Data?
    public let iconData: Data?
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
