import Foundation

public struct Logger {
    private static let logFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/webloc-preview.log")

    public static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        appendToFile(line)
    }

    public static func error(_ message: String) {
        log("ERROR: \(message)")
    }

    private static func appendToFile(_ text: String) {
        let data = Data(text.utf8)
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}
