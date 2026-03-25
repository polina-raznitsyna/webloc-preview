import Testing
import Foundation
@testable import Core

@Suite("MetadataFetcher")
struct MetadataFetcherTests {
    @Test("extracts og:title and og:image from HTML")
    func parseOGTags() throws {
        let html = """
        <html><head>
        <meta property="og:title" content="Test Title">
        <meta property="og:image" content="https://example.com/img.jpg">
        <meta property="og:site_name" content="Example">
        <title>Fallback Title</title>
        </head></html>
        """
        let meta = try MetadataFetcher.parseHTML(html, pageURL: URL(string: "https://example.com")!)
        #expect(meta.title == "Test Title")
        #expect(meta.imageURL?.absoluteString == "https://example.com/img.jpg")
    }

    @Test("falls back to <title> when no og:title")
    func fallbackTitle() throws {
        let html = "<html><head><title>Page Title</title></head></html>"
        let meta = try MetadataFetcher.parseHTML(html, pageURL: URL(string: "https://example.com")!)
        #expect(meta.title == "Page Title")
    }

    @Test("resolves relative og:image URL")
    func relativeImage() throws {
        let html = """
        <html><head>
        <meta property="og:title" content="Test">
        <meta property="og:image" content="/images/preview.png">
        </head></html>
        """
        let meta = try MetadataFetcher.parseHTML(html, pageURL: URL(string: "https://example.com/page")!)
        #expect(meta.imageURL?.absoluteString == "https://example.com/images/preview.png")
    }

    @Test("returns nil image when no og:image")
    func noImage() throws {
        let html = "<html><head><title>No Image</title></head></html>"
        let meta = try MetadataFetcher.parseHTML(html, pageURL: URL(string: "https://example.com")!)
        #expect(meta.title == "No Image")
        #expect(meta.imageURL == nil)
    }

    @Test("extracts favicon URL")
    func favicon() throws {
        let html = """
        <html><head>
        <link rel="icon" href="/favicon.png">
        <title>Test</title>
        </head></html>
        """
        let meta = try MetadataFetcher.parseHTML(html, pageURL: URL(string: "https://example.com")!)
        #expect(meta.faviconURL?.absoluteString == "https://example.com/favicon.png")
    }
}
