import CraCore
import Testing

/// The command bar ranks only the rows it can list, and the same as sorting them all.
struct CommandBarRankingTests {
    /// 5,000 history-like rows with a letter typed: scores on a coarse grid (many ties), a page in
    /// three seen twice (address variants), some open tabs.
    private static func rows(seed: UInt64) -> [CommandBarDedupe.Row] {
        var state = seed
        func next(_ n: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(n))
        }
        return (0..<5000).map { i in
            let page = i % 3 == 0 ? next(1500) : 2000 + i
            var keys = ["https://site\(page).com/a"]
            if next(10) == 0 { keys.append("github.com|title\(next(200))") }
            let score = 30 + Double(next(40)) * 2.5 + (next(4) == 0 ? 0.5 : 0)
            return CommandBarDedupe.Row(keys: keys, score: score, isOpenTab: next(50) == 0)
        }
    }

    @Test func topIsTheFullSortCut() {
        for seed: UInt64 in [1, 2, 3, 42] {
            let rows = Self.rows(seed: seed)
            let sorted = CommandBarDedupe.kept(rows)
            let pages = CommandBarDedupe.pages(rows)
            let scores = pages.map(\.score)
            for k in [0, 1, 5, 6, 10, sorted.count, sorted.count + 3] {
                let top = CommandBarRanking.top(k, of: scores).map { pages[$0] }
                #expect(top.map(\.index) == sorted.prefix(k).map(\.index))
                #expect(top.map(\.score) == sorted.prefix(k).map(\.score))
            }
        }
    }

    /// The inline completion takes the first page in ranked order that completes the text.
    @Test func firstIsTheFullSortFirstWhere() {
        let rows = Self.rows(seed: 7)
        let sorted = CommandBarDedupe.kept(rows)
        let pages = CommandBarDedupe.pages(rows)
        let scores = pages.map(\.score)
        for m in [1, 7, 97, 4999, 100_000] {
            let accept = { (row: Int) in row % m == 3 }
            let first = CommandBarRanking.first(of: scores, where: { accept(pages[$0].index) }).map { pages[$0].index }
            #expect(first == sorted.first(where: { accept($0.index) })?.index)
        }
    }

    @Test func tiesKeepTheirOrder() {
        #expect(CommandBarRanking.top(3, of: [5, 7, 7, 5, 7]) == [1, 2, 4])
        #expect(CommandBarRanking.top(9, of: [5, 7, 7, 5, 7]) == [1, 2, 4, 0, 3])
        #expect(CommandBarRanking.first(of: [5, 7, 7, 5], where: { $0 != 1 }) == 2)
        #expect(CommandBarRanking.first(of: [5, 7], where: { _ in false }) == nil)
    }

    /// The search engine's answer lists the same text again: the local rows aren't ranked anew.
    @Test func sameTextRanksOnce() {
        var memo = CommandBarRanking.Memo<String, [Int]>()
        var ranked = 0
        func rank(_ q: String) -> [Int] {
            memo.value(for: q) { ranked += 1; return [q.count] }
        }
        #expect(rank("gi") == [2])
        #expect(rank("gi") == [2])
        memo.update(for: "gi") { $0.append(9) }
        #expect(rank("gi") == [2, 9])
        #expect(ranked == 1 && memo.made == 1)
        #expect(rank("git") == [3])
        #expect(ranked == 2)
        memo.reset()
        #expect(rank("git") == [3])
        #expect(ranked == 3)
    }
}
