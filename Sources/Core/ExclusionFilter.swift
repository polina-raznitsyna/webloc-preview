import Foundation

public struct ExclusionFilter {
    private static let defaultExclusions: Set<String> = [
        ".git", "node_modules", ".Trash", ".cache", ".npm", ".cargo",
        ".rustup", ".local", "__pycache__", ".venv"
    ]

    private let libraryPath: String
    private let allExclusions: Set<String>

    public init(customExclusions: [String]) {
        self.libraryPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library").path
        self.allExclusions = Self.defaultExclusions.union(customExclusions)
    }

    public func shouldExclude(_ path: String) -> Bool {
        if path.hasPrefix(libraryPath) { return true }

        let components = path.split(separator: "/")
        for component in components {
            let name = String(component)
            if name.hasPrefix(".") && name.count > 1 {
                return true
            }
            if allExclusions.contains(name) {
                return true
            }
        }
        return false
    }
}
