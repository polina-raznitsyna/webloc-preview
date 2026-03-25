import Testing
import Foundation
@testable import Core

@Suite("FileRenamer")
struct FileRenamerTests {
    @Test("generates filename from title only")
    func basicRename() {
        let name = IconSetter.newFilename(title: "Cool Article")
        #expect(name == "Cool Article.webloc")
    }

    @Test("sanitizes invalid filename characters")
    func sanitize() {
        let name = IconSetter.newFilename(title: "What/Why: A \"Test\"")
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
    }

    @Test("truncates very long titles")
    func truncate() {
        let longTitle = String(repeating: "A", count: 300)
        let name = IconSetter.newFilename(title: longTitle)
        #expect(name.utf8.count <= 255)
    }

    @Test("handles duplicate filenames")
    func duplicateHandling() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rename-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let existing = dir.appendingPathComponent("Title.webloc")
        try Data().write(to: existing)

        let resolved = IconSetter.resolveFilename(name: "Title.webloc", in: dir)
        #expect(resolved == "Title (2).webloc")
    }
}
