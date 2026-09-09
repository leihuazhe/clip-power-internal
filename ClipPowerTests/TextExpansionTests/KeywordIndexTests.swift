import XCTest
import GRDB
@testable import ClipPower

@MainActor
final class KeywordIndexTests: XCTestCase {
    private func makeStore() throws -> SnippetStore {
        let dbQueue = try DatabaseQueue()
        _ = DatabaseManager(dbQueue: dbQueue)
        return SnippetStore(dbQueue: dbQueue)
    }

    func testMatchSuffixFindsExactKeyword() throws {
        let store = try makeStore()
        let snippet = try store.create(Snippet(name: "gitc", keyword: "gitc", plainContent: "git checkout"))

        let index = KeywordIndex(store: store)

        XCTAssertEqual(index.matchSuffix(of: "gitc"), "gitc")
        XCTAssertEqual(index.snippetID(forKeyword: "gitc"), snippet.id)
    }

    func testMatchSuffixPrefersLongerKeywordOverShorterOne() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "pwd", keyword: "pwd", plainContent: "short"))
        _ = try store.create(Snippet(name: "pwdd", keyword: "pwdd", plainContent: "long"))

        let index = KeywordIndex(store: store)

        XCTAssertEqual(index.matchSuffix(of: "pwdd"), "pwdd", "同时命中 pwd 和 pwdd 时应该选更长的那个")
    }

    func testMatchSuffixReturnsNilWhenNoKeywordMatches() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "gitc", keyword: "gitc", plainContent: "git checkout"))

        let index = KeywordIndex(store: store)

        XCTAssertNil(index.matchSuffix(of: "hello"))
    }

    func testEncryptedHiddenSnippetsAreExcludedFromIndex() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "secret", keyword: "sec", plainContent: "top-secret", visibility: .encryptedHidden))

        let index = KeywordIndex(store: store)

        XCTAssertNil(index.matchSuffix(of: "sec"), "加密隐藏的片段不应该参与自动展开")
    }

    func testSoftHiddenSnippetsAreStillIncluded() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "soft", keyword: "sft", plainContent: "soft content", visibility: .softHidden))

        let index = KeywordIndex(store: store)

        XCTAssertEqual(index.matchSuffix(of: "sft"), "sft", "软隐藏不需要鉴权，应该照常参与自动展开")
    }

    func testReloadPicksUpKeywordChangesAfterSnippetCreated() throws {
        let store = try makeStore()
        let index = KeywordIndex(store: store)
        XCTAssertNil(index.matchSuffix(of: "new"))

        _ = try store.create(Snippet(name: "new", keyword: "new", plainContent: "brand new"))
        // SnippetStore.create 会发出 .snippetsDidChange 通知，KeywordIndex 监听后自动刷新。

        XCTAssertEqual(index.matchSuffix(of: "new"), "new")
    }

    func testMatchSuffixWithinLongerTypedText() throws {
        let store = try makeStore()
        _ = try store.create(Snippet(name: "gitc", keyword: "gitc", plainContent: "git checkout"))

        let index = KeywordIndex(store: store)

        // 模拟用户已经打了一段文字，触发词出现在末尾。
        XCTAssertEqual(index.matchSuffix(of: "please run gitc"), "gitc")
    }
}
