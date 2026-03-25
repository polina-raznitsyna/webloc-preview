import Foundation

public enum WeblocFileError: Error, LocalizedError {
    case notFound(URL)
    case invalidPlist(URL)
    case missingURL(URL)

    public var errorDescription: String? {
        switch self {
        case .notFound(let url): return "File not found: \(url.path)"
        case .invalidPlist(let url): return "Invalid plist: \(url.path)"
        case .missingURL(let url): return "No URL key in plist: \(url.path)"
        }
    }
}

public struct WeblocFile {
    public static func readURL(from fileURL: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw WeblocFileError.notFound(fileURL)
        }
        guard let data = FileManager.default.contents(atPath: fileURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let urlString = plist["URL"] as? String,
              let url = URL(string: urlString) else {
            throw WeblocFileError.invalidPlist(fileURL)
        }
        return url
    }

    public static func domain(from url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
