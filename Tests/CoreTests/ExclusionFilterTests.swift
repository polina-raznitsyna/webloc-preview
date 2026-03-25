import Testing
import Foundation
@testable import Core

@Suite("ExclusionFilter")
struct ExclusionFilterTests {
    let filter = ExclusionFilter(customExclusions: [])

    @Test("excludes .git directories")
    func excludeGit() {
        #expect(filter.shouldExclude("/Users/me/project/.git/config"))
    }

    @Test("excludes node_modules")
    func excludeNodeModules() {
        #expect(filter.shouldExclude("/Users/me/project/node_modules/pkg/x.webloc"))
    }

    @Test("excludes Library")
    func excludeLibrary() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(filter.shouldExclude("\(home)/Library/Caches/something.webloc"))
    }

    @Test("excludes hidden directories")
    func excludeHidden() {
        #expect(filter.shouldExclude("/Users/me/.cache/something.webloc"))
    }

    @Test("allows normal paths")
    func allowNormal() {
        #expect(!filter.shouldExclude("/Users/me/Documents/link.webloc"))
        #expect(!filter.shouldExclude("/Users/me/Downloads/page.webloc"))
    }

    @Test("respects custom exclusions")
    func customExclusion() {
        let f = ExclusionFilter(customExclusions: ["archive", "old-stuff"])
        #expect(f.shouldExclude("/Users/me/archive/link.webloc"))
        #expect(f.shouldExclude("/Users/me/projects/old-stuff/link.webloc"))
        #expect(!f.shouldExclude("/Users/me/Documents/link.webloc"))
    }
}
