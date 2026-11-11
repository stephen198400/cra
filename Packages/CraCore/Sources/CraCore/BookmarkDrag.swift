import CoreGraphics
import Foundation

/// Where a dragged bookmark lands on the bar or in a folder's dropdown, Chrome's way: beside a
/// bookmark (the half it is over picks before or after it), beside a folder near its ends, and into
/// the folder over its middle.
public enum BookmarkDropSlot: Equatable, Sendable {
    /// Before the item at this index; the item count is the end.
    case insert(Int)
    /// Into the folder at this index (at its end).
    case into(Int)
}

public enum BookmarkDrag {
    /// One item along the bar (x) or down a dropdown (y), in order.
    public struct Span: Equatable, Sendable {
        public var start: CGFloat
        public var end: CGFloat
        public var isFolder: Bool
        public init(start: CGFloat, end: CGFloat, isFolder: Bool) {
            self.start = start
            self.end = end
            self.isFolder = isFolder
        }
    }

    /// The part of a folder's length at each end that still drops beside it rather than into it.
    public static let folderEdge: CGFloat = 0.25

    /// The slot under `p`. Before the first item is 0, past the last the end; in a gap between two
    /// items, the boundary between them.
    public static func slot(at p: CGFloat, in spans: [Span]) -> BookmarkDropSlot {
        for (i, s) in spans.enumerated() {
            if p < s.start { return .insert(i) }
            guard p <= s.end else { continue }
            let len = max(s.end - s.start, 1)
            let f = (p - s.start) / len
            if s.isFolder {
                if f < folderEdge { return .insert(i) }
                if f > 1 - folderEdge { return .insert(i + 1) }
                return .into(i)
            }
            return .insert(f < 0.5 ? i : i + 1)
        }
        return .insert(spans.count)
    }

    /// The move a drop of `id` at `slot` among `parent`'s `children` makes: the folder and the index
    /// for `BookmarkTree.move` (an index counting the folder's items before the move). nil when the
    /// tree won't take it (a folder into itself or one inside it, an unknown id).
    public static func destination(of id: UUID, at slot: BookmarkDropSlot, parent: UUID,
                                   children: [BookmarkNode], in tree: BookmarkTree) -> (folder: UUID, index: Int?)? {
        let target: (folder: UUID, index: Int?)
        switch slot {
        case .insert(let i):
            target = (parent, min(max(0, i), children.count))
        case .into(let i):
            guard children.indices.contains(i), children[i].isFolder else { return nil }
            target = (children[i].id, nil)
        }
        return tree.canMove(id: id, to: target.folder) ? target : nil
    }
}

extension BookmarkTree {
    /// Whether `id` may go into `folder`: not a root, not into a bookmark, and a folder never into
    /// itself or one inside it.
    public func canMove(id: UUID, to folder: UUID) -> Bool {
        guard id != Self.barID, id != Self.otherID, let moving = node(id), parent(of: id) != nil,
              let target = node(folder), target.isFolder else { return false }
        return !(moving.isFolder && (moving.id == folder || BookmarkNode.contains(moving, folder)))
    }
}
