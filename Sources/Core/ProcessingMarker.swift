import Foundation

public struct ProcessingMarker {
    private static let attrName = "com.webloc-preview.processed"

    public static func isProcessed(_ fileURL: URL) -> Bool {
        let path = fileURL.path
        let size = getxattr(path, attrName, nil, 0, 0, 0)
        return size >= 0
    }

    public static func markProcessed(_ fileURL: URL) throws {
        let data = Data("1".utf8)
        let result = data.withUnsafeBytes { bytes in
            setxattr(fileURL.path, attrName, bytes.baseAddress, data.count, 0, 0)
        }
        if result != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    public static func removeMark(_ fileURL: URL) throws {
        let result = removexattr(fileURL.path, attrName, 0)
        if result != 0 && errno != ENOATTR {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
