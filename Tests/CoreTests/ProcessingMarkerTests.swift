import Testing
import Foundation
@testable import Core

@Suite("ProcessingMarker")
struct ProcessingMarkerTests {
    @Test("marks file as processed and detects it")
    func markAndCheck() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-test-\(UUID().uuidString).webloc")
        try "test".data(using: .utf8)!.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(!ProcessingMarker.isProcessed(tmp))
        try ProcessingMarker.markProcessed(tmp)
        #expect(ProcessingMarker.isProcessed(tmp))
    }

    @Test("removes processing mark")
    func removeMark() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-rm-\(UUID().uuidString).webloc")
        try "test".data(using: .utf8)!.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ProcessingMarker.markProcessed(tmp)
        try ProcessingMarker.removeMark(tmp)
        #expect(!ProcessingMarker.isProcessed(tmp))
    }
}
