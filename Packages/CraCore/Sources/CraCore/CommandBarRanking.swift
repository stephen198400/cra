import Foundation

/// The command bar ranks every match (up to 5,000 history entries with a letter or two typed) but
/// lists five rows. These pick the rows a stable sort by score would put first without sorting
/// the rest, so a keystroke builds rows only for what can show.
public enum CommandBarRanking {
    /// Positions of the `k` best scores, best first, equal scores in the order given: the same as
    /// a stable sort by descending score cut to `k`.
    public static func top(_ k: Int, of scores: [Double]) -> [Int] {
        guard k > 0 else { return [] }
        var best: [Int] = []
        best.reserveCapacity(min(k, scores.count) + 1)
        for (i, s) in scores.enumerated() {
            // Later positions lose ties, so a score enters only above the worst one held.
            if best.count == k, s <= scores[best[best.count - 1]] { continue }
            var lo = 0, hi = best.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if scores[best[mid]] >= s { lo = mid + 1 } else { hi = mid }
            }
            best.insert(i, at: lo)
            if best.count > k { best.removeLast() }
        }
        return best
    }

    /// The first position in that order that `accept` takes: its best score, the earliest among
    /// equals. The same as the stable sort's `first(where:)`.
    public static func first(of scores: [Double], where accept: (Int) -> Bool) -> Int? {
        var found: Int?
        for (i, s) in scores.enumerated() where found.map({ s > scores[$0] }) ?? true {
            if accept(i) { found = i }
        }
        return found
    }

    /// The last ranking, kept while its inputs stay the same: the search engine's answer lists
    /// again with the local rows already ranked for that text.
    public struct Memo<Key: Equatable, Value> {
        private var last: (key: Key, value: Value)?
        /// How many times `value(for:make:)` ranked anew.
        public private(set) var made = 0

        public init() {}

        public mutating func value(for key: Key, make: () -> Value) -> Value {
            if let last, last.key == key { return last.value }
            let value = make()
            made += 1
            last = (key, value)
            return value
        }

        /// Changes the value held for `key`, if that is the one held (a lazily worked-out part).
        public mutating func update(for key: Key, _ change: (inout Value) -> Void) {
            guard var held = last, held.key == key else { return }
            last = nil
            change(&held.value)
            last = held
        }

        public mutating func reset() { last = nil }
    }
}
