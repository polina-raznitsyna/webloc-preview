import Foundation
import SwiftSoup

public struct PageMetadata: Sendable {
    public let title: String
    public let imageURL: URL?
    public let faviconURL: URL?
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

        // Favicon: link[rel~=icon]
        let faviconHref = try doc.select("link[rel~=icon]").first()?.attr("href")
        let faviconURL = faviconHref.flatMap { resolveURL($0, base: pageURL) }

        return PageMetadata(title: title, imageURL: imageURL, faviconURL: faviconURL)
    }

    /// Fetch HTML from URL and parse metadata. Timeout: 15 seconds.
    public static func fetch(url: URL) async throws -> PageMetadata {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

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

    private static func resolveURL(_ string: String, base: URL) -> URL? {
        if let absolute = URL(string: string), absolute.scheme != nil {
            return absolute
        }
        return URL(string: string, relativeTo: base)?.absoluteURL
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
