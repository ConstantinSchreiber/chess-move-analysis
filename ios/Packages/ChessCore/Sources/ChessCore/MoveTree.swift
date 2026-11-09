/// A tree of explored moves starting from a root position. Every node stores its resulting position,
/// so navigating is O(1). Node 0 is the root.
public struct MoveTree: Sendable, Equatable {
    public typealias NodeID = Int

    public struct Node: Sendable, Equatable, Identifiable {
        public let id: NodeID
        public let parent: NodeID?
        public let move: Move?
        public let san: String?
        public let position: Position
        /// The first child is the main continuation.
        public internal(set) var children: [NodeID]
        /// Number of half-moves from the root.
        public let ply: Int
    }

    public private(set) var nodes: [Node]
    public static let root: NodeID = 0

    public init(root position: Position) {
        nodes = [Node(id: 0, parent: nil, move: nil, san: nil, position: position, children: [], ply: 0)]
    }

    public subscript(id: NodeID) -> Node { nodes[id] }
    public var rootPosition: Position { nodes[0].position }

    /// Adds `move` after `node` (reusing an existing identical child). Returns nil if the move is illegal.
    @discardableResult
    public mutating func add(_ move: Move, after node: NodeID) -> NodeID? {
        if let existing = nodes[node].children.first(where: { nodes[$0].move == move }) { return existing }
        let position = nodes[node].position
        guard let next = position.playing(move) else { return nil }
        let id = nodes.count
        nodes.append(Node(id: id, parent: node, move: move, san: position.san(for: move), position: next,
                          children: [], ply: nodes[node].ply + 1))
        nodes[node].children.append(id)
        return id
    }

    /// Adds a sequence of UCI moves; returns the id of the last node added.
    @discardableResult
    public mutating func add(uciLine: [String], after node: NodeID) -> NodeID {
        var current = node
        for uci in uciLine {
            guard let move = Move(uci: uci), let next = add(move, after: current) else { break }
            current = next
        }
        return current
    }

    /// Root → node, inclusive.
    public func path(to node: NodeID) -> [NodeID] {
        var result: [NodeID] = []
        var current: NodeID? = node
        while let id = current {
            result.append(id)
            current = nodes[id].parent
        }
        return result.reversed()
    }

    /// The line shown to the user: root → `node`, then following first children to the end.
    public func line(through node: NodeID) -> [NodeID] {
        var result = path(to: node)
        var current = node
        while let next = nodes[current].children.first {
            result.append(next)
            current = next
        }
        return result
    }

    /// Moves from the root to `node`.
    public func moves(to node: NodeID) -> [Move] {
        path(to: node).compactMap { nodes[$0].move }
    }

    /// The node reached by following `moves` from the root, if that line exists.
    public func node(following moves: [Move]) -> NodeID? {
        var current = Self.root
        for move in moves {
            guard let next = nodes[current].children.first(where: { nodes[$0].move == move }) else { return nil }
            current = next
        }
        return current
    }

    /// Promotes `node`'s branch to be the main continuation at every fork above it.
    public mutating func promote(_ node: NodeID) {
        var child = node
        while let parent = nodes[child].parent {
            if let index = nodes[parent].children.firstIndex(of: child), index > 0 {
                nodes[parent].children.remove(at: index)
                nodes[parent].children.insert(child, at: 0)
            }
            child = parent
        }
    }

    /// Removes `node` and its subtree. The root can't be deleted. Node ids are compacted afterwards,
    /// so callers should re-resolve ids; returns the parent id (valid after compaction).
    @discardableResult
    public mutating func delete(_ node: NodeID) -> NodeID {
        guard node != Self.root, let parent = nodes[node].parent else { return Self.root }
        var doomed = Set<NodeID>()
        var stack = [node]
        while let id = stack.popLast() {
            doomed.insert(id)
            stack.append(contentsOf: nodes[id].children)
        }
        var remap: [NodeID: NodeID] = [:]
        var kept: [Node] = []
        for n in nodes where !doomed.contains(n.id) {
            remap[n.id] = kept.count
            kept.append(n)
        }
        nodes = kept.map { n in
            Node(id: remap[n.id]!, parent: n.parent.flatMap { remap[$0] }, move: n.move, san: n.san,
                 position: n.position, children: n.children.compactMap { remap[$0] }, ply: n.ply)
        }
        return remap[parent] ?? Self.root
    }

    /// Move number label for the node's move, e.g. "12." for White, "12…" for Black.
    public func moveNumberLabel(for node: NodeID) -> String {
        guard let parent = nodes[node].parent else { return "" }
        let before = nodes[parent].position
        return before.sideToMove == .white ? "\(before.fullmoveNumber)." : "\(before.fullmoveNumber)…"
    }
}
