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
    /// This bypasses anti-bot JS challenges that block plain HTTP.
    public func fetchMetadataViaWebKit(url: URL) async throws -> PageMetadata {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let config = WKWebViewConfiguration()
                let webView = WKWebView(
                    frame: NSRect(x: 0, y: 0, width: 1200, height: 800),
                    configuration: config
                )
                let delegate = MetadataExtractionDelegate(
                    continuation: continuation,
                    webView: webView,
                    pageURL: url
                )
                webView.navigationDelegate = delegate
                objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                webView.load(URLRequest(url: url))

                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak delegate] in
                    guard let delegate = delegate, !delegate.resumed else { return }
                    delegate.resumed = true
                    webView.stopLoading()
                    continuation.resume(throwing: ScreenshotError.timeout)
                }
            }
        }
    }

    /// Take a screenshot of a web page. Returns PNG data.
    public func takeScreenshot(of url: URL, width: Int = 1200, height: Int = 800) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let config = WKWebViewConfiguration()
                let webView = WKWebView(
                    frame: NSRect(x: 0, y: 0, width: width, height: height),
                    configuration: config
                )
                let delegate = ScreenshotNavigationDelegate(
                    continuation: continuation,
                    webView: webView
                )
                webView.navigationDelegate = delegate
                objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                webView.load(URLRequest(url: url))

                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak delegate] in
                    guard let delegate = delegate, !delegate.resumed else { return }
                    delegate.resumed = true
                    webView.stopLoading()
                    continuation.resume(throwing: ScreenshotError.timeout)
                }
            }
        }
    }
}

// MARK: - Metadata extraction via WebKit

private class MetadataExtractionDelegate: NSObject, WKNavigationDelegate {
    let continuation: CheckedContinuation<PageMetadata, Error>
    let webView: WKWebView
    let pageURL: URL
    var resumed = false

    init(continuation: CheckedContinuation<PageMetadata, Error>, webView: WKWebView, pageURL: URL) {
        self.continuation = continuation
        self.webView = webView
        self.pageURL = pageURL
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !resumed else { return }
        // Wait 8 seconds for JS to render (SPAs and anti-bot pages need time)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [self] in
            guard !resumed else { return }
            resumed = true

            let js = """
            (function() {
                var ogTitle = document.querySelector('meta[property="og:title"]');
                var ogImage = document.querySelector('meta[property="og:image"]');
                var favicon = document.querySelector('link[rel*="icon"]');
                var icons = document.querySelectorAll('link[rel*="icon"]');
                var bestIcon = null;
                var bestSize = 0;
                icons.forEach(function(icon) {
                    var sizes = icon.getAttribute('sizes') || '';
                    var size = parseInt(sizes) || 0;
                    if (size > bestSize || !bestIcon) {
                        bestIcon = icon.getAttribute('href');
                        bestSize = size;
                    }
                });
                return JSON.stringify({
                    title: (ogTitle ? ogTitle.content : '') || document.title || '',
                    image: ogImage ? ogImage.content : '',
                    favicon: bestIcon || ''
                });
            })()
            """

            webView.evaluateJavaScript(js) { result, error in
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
                    // Fallback: just use document.title
                    webView.evaluateJavaScript("document.title") { titleResult, _ in
                        let title = titleResult as? String ?? self.pageURL.absoluteString
                        self.continuation.resume(returning: PageMetadata(
                            title: title, imageURL: nil, faviconURL: nil
                        ))
                    }
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
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !resumed else { return }
        resumed = true
        continuation.resume(throwing: error)
    }

    private func resolveURL(_ string: String) -> URL? {
        if let absolute = URL(string: string), absolute.scheme != nil {
            return absolute
        }
        return URL(string: string, relativeTo: pageURL)?.absoluteURL
    }
}

// MARK: - Screenshot delegate

private class ScreenshotNavigationDelegate: NSObject, WKNavigationDelegate {
    let continuation: CheckedContinuation<Data, Error>
    let webView: WKWebView
    var resumed = false

    init(continuation: CheckedContinuation<Data, Error>, webView: WKWebView) {
        self.continuation = continuation
        self.webView = webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !resumed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
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

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !resumed else { return }
        resumed = true
        continuation.resume(throwing: error)
    }
}
