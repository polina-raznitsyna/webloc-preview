import Testing
import Foundation
@testable import Core

@Suite("WeblocFile")
struct WeblocFileTests {
    @Test("extracts URL from valid .webloc plist")
    func extractURL() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict><key>URL</key><string>https://www.youtube.com/watch?v=abc123</string></dict>
        </plist>
        """.data(using: .utf8)!

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).webloc")
        try plist.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = try WeblocFile.readURL(from: tmp)
        #expect(url.absoluteString == "https://www.youtube.com/watch?v=abc123")
    }

    @Test("extracts domain from URL")
    func extractDomain() throws {
        let url = URL(string: "https://www.youtube.com/watch?v=abc123")!
        let domain = WeblocFile.domain(from: url)
        #expect(domain == "youtube.com")
    }

    @Test("strips www prefix from domain")
    func stripWWW() throws {
        let url = URL(string: "https://www.litres.ru/book/123")!
        let domain = WeblocFile.domain(from: url)
        #expect(domain == "litres.ru")
    }

    @Test("throws on invalid plist")
    func invalidPlist() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID().uuidString).webloc")
        try "not a plist".data(using: .utf8)!.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(throws: WeblocFileError.self) {
            try WeblocFile.readURL(from: tmp)
        }
    }
}
