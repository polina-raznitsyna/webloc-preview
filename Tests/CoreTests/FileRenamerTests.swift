import Testing
import Foundation
@testable import Core

@Suite("FileRenamer")
struct FileRenamerTests {
    @Test("generates correct filename from title and domain")
    func basicRename() {
        let name = IconSetter.newFilename(title: "Cool Article", domain: "example.com")
        #expect(name == "Cool Article \u{2014} example.com.webloc")
    }

    @Test("sanitizes invalid filename characters")
    func sanitize() {
        let name = IconSetter.newFilename(title: "What/Why: A \"Test\"", domain: "example.com")
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
    }

    @Test("truncates very long titles")
    func truncate() {
        let longTitle = String(repeating: "A", count: 300)
        let name = IconSetter.newFilename(title: longTitle, domain: "example.com")
        #expect(name.utf8.count <= 255)
    }

    @Test("handles duplicate filenames")
    func duplicateHandling() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rename-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let existing = dir.appendingPathComponent("Title \u{2014} example.com.webloc")
        try Data().write(to: existing)

        let resolved = IconSetter.resolveFilename(name: "Title \u{2014} example.com.webloc", in: dir)
        #expect(resolved == "Title \u{2014} example.com (2).webloc")
    }
}
