import AppKit
import Foundation

public struct IconSetter {
    /// Set a custom icon on a .webloc file
    public static func setIcon(_ image: NSImage, for fileURL: URL) -> Bool {
        NSWorkspace.shared.setIcon(image, forFile: fileURL.path, options: [])
    }

    /// Rename a .webloc file based on title and domain.
    /// Returns the new file URL, or the original if rename fails.
    public static func renameFile(at fileURL: URL, title: String, domain: String) throws -> URL {
        let newName = newFilename(title: title, domain: domain)
        let dir = fileURL.deletingLastPathComponent()
        let resolvedName = resolveFilename(name: newName, in: dir)
        let newURL = dir.appendingPathComponent(resolvedName)

        if newURL.path != fileURL.path {
            try FileManager.default.moveItem(at: fileURL, to: newURL)
        }
        return newURL
    }

    /// Generate filename: "{title} — {domain}.webloc"
    public static func newFilename(title: String, domain: String) -> String {
        let sanitized = sanitize(title)
        let suffix = " \u{2014} \(domain).webloc"
        let maxTitleBytes = 255 - suffix.utf8.count
        let truncated = truncateToUTF8(sanitized, maxBytes: maxTitleBytes)
        return truncated + suffix
    }

    /// If filename exists, append (2), (3), etc.
    public static func resolveFilename(name: String, in directory: URL) -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.appendingPathComponent(name).path) {
            return name
        }

        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension

        var counter = 2
        while true {
            let candidate = "\(base) (\(counter)).\(ext)"
            if !fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
                return candidate
            }
            counter += 1
        }
    }

    private static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        return name.unicodeScalars.filter { !forbidden.contains($0) }
            .map(String.init).joined()
    }

    private static func truncateToUTF8(_ string: String, maxBytes: Int) -> String {
        guard string.utf8.count > maxBytes else { return string }
        var result = string
        while result.utf8.count > maxBytes {
            result = String(result.dropLast())
        }
        return result
    }
}
