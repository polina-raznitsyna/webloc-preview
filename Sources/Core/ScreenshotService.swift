import AppKit
import WebKit
import Foundation

public enum ScreenshotError: Error {
    case timeout
    case renderFailed
}

public final class ScreenshotService: @unchecked Sendable {
    public static let shared = ScreenshotService()

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

                // Store delegate to prevent deallocation
                objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

                webView.load(URLRequest(url: url))

                // Timeout after 15 seconds
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
        // Wait 2 seconds for JS rendering
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
