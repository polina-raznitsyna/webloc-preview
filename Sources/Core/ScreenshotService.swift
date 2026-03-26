import AppKit
import WebKit
import Foundation

public enum ScreenshotError: Error {
    case timeout
    case renderFailed
}

public final class ScreenshotService: @unchecked Sendable {
    public static let shared = ScreenshotService()

    /// Load page in WebKit and extract OG metadata from rendered DOM.
    /// Polls for up to 20 seconds until real content appears (handles JS challenges).
    public func fetchMetadataViaWebKit(url: URL) async throws -> PageMetadata {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let config = WKWebViewConfiguration()
                let webView = WKWebView(
                    frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
                    configuration: config
                )
                webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

                let poller = MetadataPoller(
                    webView: webView,
                    pageURL: url,
                    continuation: continuation,
                    maxWait: 22
                )
                webView.navigationDelegate = poller
                objc_setAssociatedObject(webView, "poller", poller, .OBJC_ASSOCIATION_RETAIN)
                webView.load(URLRequest(url: url))
            }
        }
    }

    /// Take a screenshot of a web page. Returns PNG data.
    /// Also polls waiting for JS challenges to resolve.
    public func takeScreenshot(of url: URL, width: Int = 1200, height: Int = 800) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let config = WKWebViewConfiguration()
                let webView = WKWebView(
                    frame: NSRect(x: 0, y: 0, width: width, height: height),
                    configuration: config
                )
                webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

                let delegate = ScreenshotPoller(
                    webView: webView,
                    continuation: continuation,
                    maxWait: 22
                )
                webView.navigationDelegate = delegate
                objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                webView.load(URLRequest(url: url))
            }
        }
    }
}

// MARK: - Metadata extraction with polling

/// Polls WebView every 2 seconds until real content appears or timeout
private class MetadataPoller: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let pageURL: URL
    let continuation: CheckedContinuation<PageMetadata, Error>
    let maxWait: TimeInterval
    var resumed = false
    var pollTimer: Timer?
    var startTime: Date?

    private static let antiBotTitles: Set<String> = [
        "почти готово...", "just a moment...", "вы не робот?",
        "access denied", "attention required", "checking your browser",
        "please wait...", "one moment, please...", "ddos protection",
        "security check"
    ]

    init(webView: WKWebView, pageURL: URL, continuation: CheckedContinuation<PageMetadata, Error>, maxWait: TimeInterval) {
        self.webView = webView
        self.pageURL = pageURL
        self.continuation = continuation
        self.maxWait = maxWait
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !resumed else { return }
        startTime = Date()
        startPolling()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !resumed else { return }
        resumed = true
        pollTimer?.invalidate()
        continuation.resume(throwing: error)
    }

    private func startPolling() {
        pollOnce()
    }

    private func pollOnce() {
        guard !resumed else { return }

        // Timeout check
        if let start = startTime, Date().timeIntervalSince(start) > maxWait {
            extractAndReturn()
            return
        }

        // Check if we have real content
        webView.evaluateJavaScript("""
            (function() {
                var og = document.querySelector('meta[property="og:title"]');
                return JSON.stringify({
                    title: document.title || '',
                    ogTitle: og ? og.content : ''
                });
            })()
        """) { [weak self] result, _ in
            guard let self = self, !self.resumed else { return }

            if let json = result as? String,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {

                let title = dict["title"]?.lowercased() ?? ""
                let ogTitle = dict["ogTitle"] ?? ""

                let isAntiBot = Self.antiBotTitles.contains(where: { title.contains($0) }) || title.isEmpty
                let hasOgTitle = !ogTitle.isEmpty && ogTitle != "Яндекс"

                if !isAntiBot || hasOgTitle {
                    self.extractAndReturn()
                    return
                }
            }

            // Schedule next poll
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.pollOnce()
            }
        }
    }

    private func extractAndReturn() {
        guard !resumed else { return }
        resumed = true

        let js = """
        (function() {
            var ogTitle = document.querySelector('meta[property="og:title"]');
            var ogImage = document.querySelector('meta[property="og:image"]');
            var icons = document.querySelectorAll('link[rel*="icon"]');
            var bestIcon = null, bestSize = 0;
            icons.forEach(function(icon) {
                var size = parseInt(icon.getAttribute('sizes') || '0') || 0;
                if (size > bestSize || !bestIcon) { bestIcon = icon.href; bestSize = size; }
            });
            return JSON.stringify({
                title: (ogTitle ? ogTitle.content : '') || document.title || '',
                image: ogImage ? ogImage.content : '',
                favicon: bestIcon || ''
            });
        })()
        """

        webView.evaluateJavaScript(js) { result, _ in
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
                self.continuation.resume(returning: PageMetadata(
                    title: self.pageURL.absoluteString, imageURL: nil, faviconURL: nil
                ))
                return
            }

            let title = dict["title"]?.nilIfEmpty ?? self.pageURL.absoluteString
            let imageURL = dict["image"]?.nilIfEmpty.flatMap { self.resolveURL($0) }
            let faviconURL = dict["favicon"]?.nilIfEmpty.flatMap { self.resolveURL($0) }

            self.continuation.resume(returning: PageMetadata(
                title: title, imageURL: imageURL, faviconURL: faviconURL
            ))
        }
    }

    private func resolveURL(_ string: String) -> URL? {
        if let abs = URL(string: string), abs.scheme != nil { return abs }
        return URL(string: string, relativeTo: pageURL)?.absoluteURL
    }
}

// MARK: - Screenshot with polling

private class ScreenshotPoller: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let continuation: CheckedContinuation<Data, Error>
    let maxWait: TimeInterval
    var resumed = false
    var startTime: Date?

    private static let antiBotTitles: Set<String> = [
        "почти готово...", "just a moment...", "вы не робот?",
        "access denied", "checking your browser", "please wait"
    ]

    init(webView: WKWebView, continuation: CheckedContinuation<Data, Error>, maxWait: TimeInterval) {
        self.webView = webView
        self.continuation = continuation
        self.maxWait = maxWait
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !resumed else { return }
        startTime = Date()
        startPolling()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !resumed else { return }
        resumed = true
        continuation.resume(throwing: error)
    }

    private func startPolling() {
        pollOnce()
    }

    private func pollOnce() {
        guard !resumed else { return }

        if let start = startTime, Date().timeIntervalSince(start) > maxWait {
            takeSnapshot()
            return
        }

        webView.evaluateJavaScript("document.title") { [weak self] result, _ in
            guard let self = self, !self.resumed else { return }
            let title = (result as? String ?? "").lowercased()
            let isAntiBot = Self.antiBotTitles.contains(where: { title.contains($0) }) || title.isEmpty
            if !isAntiBot {
                // Wait 1 extra second for rendering
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.takeSnapshot()
                }
            } else {
                // Schedule next poll
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.pollOnce()
                }
            }
        }
    }

    private func takeSnapshot() {
        guard !resumed else { return }
        resumed = true
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { image, error in
            if let image = image,
               let tiff = image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiff),
               let png = bitmapRep.representation(using: .png, properties: [:]) {
                self.continuation.resume(returning: png)
            } else {
                self.continuation.resume(throwing: error ?? ScreenshotError.renderFailed)
            }
        }
    }
}
