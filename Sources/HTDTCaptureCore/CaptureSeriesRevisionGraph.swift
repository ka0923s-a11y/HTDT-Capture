import Foundation

/// A lineage diagnostic inside one capture series' revision graph
/// (issue bolph71656-ai/HTDT-Capture#396). Diagnostics describe declared-but-unresolved or
/// inconsistent lineage — they never guess at repair.
public enum CaptureSeriesRevisionDiagnostic:
    Sendable,
    Equatable
{
    /// A revision declares a parent that is not present anywhere in the
    /// local inventory — history between the two is incomplete.
    case missingPredecessor(
        revision: CaptureRevisionID,
        parent: CaptureRevisionID
    )
    /// A revision declares a parent that resolves locally but belongs
    /// to a different capture series — a cross-series lineage edge the
    /// series graph keeps visible instead of silently absorbing.
    case crossSeriesParent(
        revision: CaptureRevisionID,
        parent: CaptureRevisionID,
        parentSeries: CaptureSeriesID
    )
    /// The declared parent edges form a cycle (only possible with
    /// inconsistent imported lineage; the app's own writers reject
    /// self-parenthood and can never produce one).
    case cyclicTopology([CaptureRevisionID])
}

/// Read-side revision-fork graph for one capture series (issue bolph71656-ai/HTDT-Capture#396).
///
/// Every edge is declared lineage from the validated manifest's
/// `parent_revision_id` — UUID identity only, never device-local
/// counters or `finalized_at` ordering. A series can hold several
/// heads (a fork) when two revisions declare the same parent or when
/// sibling roots coexist; the newest timestamped revision is NOT
/// implicitly "the latest" in a branched series.
public struct CaptureSeriesRevisionGraph:
    Sendable,
    Equatable
{
    /// One revision as a graph node: its declared parent edge and the
    /// local children that declare it as parent.
    public struct Node: Sendable, Equatable {
        public let revisionID: CaptureRevisionID
        public let parentRevisionID: CaptureRevisionID?
        /// Whether the declared parent resolves locally inside this
        /// series. false both for missing predecessors and for
        /// cross-series parents (which resolve outside this graph).
        public let parentResolvedInSeries: Bool
        public let finalizedAtUTC: String
        /// Local revisions that declare this one as their parent, in
        /// deterministic (finalizedAtUTC, id) order.
        public let children: [CaptureRevisionID]

        public init(
            revisionID: CaptureRevisionID,
            parentRevisionID: CaptureRevisionID?,
            parentResolvedInSeries: Bool,
            finalizedAtUTC: String,
            children: [CaptureRevisionID]
        ) {
            self.revisionID = revisionID
            self.parentRevisionID = parentRevisionID
            self.parentResolvedInSeries = parentResolvedInSeries
            self.finalizedAtUTC = finalizedAtUTC
            self.children = children
        }
    }

    public let captureSeriesID: CaptureSeriesID
    /// Every revision of this series present in the local inventory.
    public let nodes: [CaptureRevisionID: Node]
    /// Revisions that declare no parent.
    public let roots: [CaptureRevisionID]
    /// Revisions with no local children — the branch tips. Ordered by
    /// finalizedAtUTC (then id) so presentation is deterministic; when
    /// more than one head exists the order is display order only, never
    /// precedence.
    public let heads: [CaptureRevisionID]
    public let diagnostics: [CaptureSeriesRevisionDiagnostic]

    /// Builds the graph for `captureSeriesID` from every record in
    /// `allRecords`. Passing the full inventory (not just the series'
    /// slice) lets cross-series parent edges be diagnosed instead of
    /// misread as missing predecessors.
    public init(
        allRecords: [PersistedCaptureRecord],
        captureSeriesID: CaptureSeriesID
    ) {
        self.captureSeriesID = captureSeriesID
        let byID = Dictionary(
            allRecords.map { ($0.captureRevisionID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let order: (PersistedCaptureRecord, PersistedCaptureRecord)
            -> Bool = { a, b in
                a.finalizedAtUTC == b.finalizedAtUTC
                    ? a.captureRevisionID.description
                        < b.captureRevisionID.description
                    : a.finalizedAtUTC < b.finalizedAtUTC
            }

        var diagnostics: [CaptureSeriesRevisionDiagnostic] = []
        var childrenOf: [CaptureRevisionID: [CaptureRevisionID]] = [:]
        var parentResolved: [CaptureRevisionID: Bool] = [:]
        for record in Self.seriesRecords(
            allRecords,
            captureSeriesID
        ).sorted(by: order)
        {
            guard let parentID = record.parentRevisionID else {
                continue
            }
            if let parent = byID[parentID] {
                if parent.captureSeriesID == captureSeriesID {
                    parentResolved[record.captureRevisionID] = true
                    childrenOf[parentID, default: []].append(
                        record.captureRevisionID
                    )
                } else {
                    parentResolved[record.captureRevisionID] = false
                    diagnostics.append(
                        .crossSeriesParent(
                            revision: record.captureRevisionID,
                            parent: parentID,
                            parentSeries: parent.captureSeriesID
                        )
                    )
                }
            } else {
                parentResolved[record.captureRevisionID] = false
                diagnostics.append(
                    .missingPredecessor(
                        revision: record.captureRevisionID,
                        parent: parentID
                    )
                )
            }
        }

        var nodes: [CaptureRevisionID: Node] = [:]
        for record in Self.seriesRecords(
            allRecords,
            captureSeriesID
        ) {
            let children =
                (childrenOf[record.captureRevisionID] ?? [])
                .sorted { a, b in
                    guard let ra = byID[a], let rb = byID[b] else {
                        return a.description < b.description
                    }
                    return order(ra, rb)
                }
            nodes[record.captureRevisionID] = Node(
                revisionID: record.captureRevisionID,
                parentRevisionID: record.parentRevisionID,
                parentResolvedInSeries:
                    parentResolved[record.captureRevisionID] ?? true,
                finalizedAtUTC: record.finalizedAtUTC,
                children: children
            )
        }

        var visited: Set<CaptureRevisionID> = []
        for record in Self.seriesRecords(
            allRecords,
            captureSeriesID
        ) {
            var chain: [CaptureRevisionID] = []
            var cursor: CaptureRevisionID? = record.captureRevisionID
            var localSeen: Set<CaptureRevisionID> = []
            var hitCycle = false
            while let current = cursor {
                if localSeen.contains(current) {
                    hitCycle = true
                    break
                }
                if visited.contains(current) { break }
                localSeen.insert(current)
                chain.append(current)
                cursor = nodes[current]?.parentRevisionID.flatMap {
                    parentID in
                    nodes[parentID] != nil ? parentID : nil
                }
            }
            if hitCycle {
                diagnostics.append(.cyclicTopology(chain))
            }
            visited.formUnion(localSeen)
        }

        self.nodes = nodes
        self.diagnostics = diagnostics
        self.roots = Self.seriesRecords(
            allRecords,
            captureSeriesID
        )
            .filter { $0.parentRevisionID == nil }
            .sorted(by: order)
            .map(\.captureRevisionID)
        self.heads = Self.seriesRecords(
            allRecords,
            captureSeriesID
        )
            .filter {
                nodes[$0.captureRevisionID]?.children.isEmpty != false
            }
            .sorted(by: order)
            .map(\.captureRevisionID)
    }

    private static func seriesRecords(
        _ allRecords: [PersistedCaptureRecord],
        _ seriesID: CaptureSeriesID
    ) -> [PersistedCaptureRecord] {
        allRecords.filter { $0.captureSeriesID == seriesID }
    }

    /// True when the series resolves to exactly one head — the common
    /// linear case where "latest" is unambiguous.
    public var hasSingleHead: Bool {
        heads.count == 1
    }

    /// True when the series has more than one branch tip.
    public var isBranched: Bool {
        heads.count > 1
    }

    /// The strict ancestor chain of `revisionID`, nearest parent
    /// first. Stops at the last locally resolved ancestor — a missing
    /// predecessor or cycle boundary ends the walk; `truncated` reports
    /// whether a declared parent remained unresolved when the chain
    /// ended.
    public func ancestors(
        of revisionID: CaptureRevisionID
    ) -> (chain: [CaptureRevisionID], truncated: Bool) {
        var chain: [CaptureRevisionID] = []
        var seen: Set<CaptureRevisionID> = [revisionID]
        var cursor = nodes[revisionID]?.parentRevisionID
        var truncated = false
        while let current = cursor {
            guard let node = nodes[current], !seen.contains(current)
            else {
                truncated = true
                break
            }
            chain.append(current)
            seen.insert(current)
            cursor = node.parentRevisionID
        }
        return (chain, truncated)
    }

    /// All revisions that declare `revisionID` as an ancestor through
    /// resolved local edges — used to describe lineage consequences of
    /// deletion (deleting a revision never deletes its descendants).
    public func descendants(
        of revisionID: CaptureRevisionID
    ) -> [CaptureRevisionID] {
        var result: [CaptureRevisionID] = []
        var queue: [CaptureRevisionID] =
            nodes[revisionID]?.children ?? []
        var seen: Set<CaptureRevisionID> = Set(queue)
        while let current = queue.first {
            queue.removeFirst()
            result.append(current)
            for child in nodes[current]?.children ?? []
            where !seen.contains(child) {
                seen.insert(child)
                queue.append(child)
            }
        }
        return result
    }

    /// The head(s) reachable from `revisionID` walking downward over
    /// resolved edges — how many branch tips sit above a node.
    public func headCount(
        above revisionID: CaptureRevisionID
    ) -> Int {
        var count = 0
        var queue: [CaptureRevisionID] = [revisionID]
        var seen: Set<CaptureRevisionID> = [revisionID]
        while let current = queue.first {
            queue.removeFirst()
            let children = nodes[current]?.children ?? []
            if children.isEmpty {
                count += 1
            }
            for child in children where !seen.contains(child) {
                seen.insert(child)
                queue.append(child)
            }
        }
        return count
    }
}

/// How an incoming bundle's declared lineage classifies against the
/// local inventory (issue bolph71656-ai/HTDT-Capture#396 §7). The classification is computed
/// from UUID-declared edges only — timestamps never drive it.
public enum ImportLineageClassification:
    String,
    Sendable,
    Equatable
{
    /// The revision id is already present locally under the same
    /// series with the same declared parent — a byte-identity
    /// re-import.
    case exactDuplicate = "exact_duplicate"
    /// The revision id is already present locally with a different
    /// declared parent or a different series — identity conflict; the
    /// import must be refused/quarantined rather than merged.
    case identityConflict = "identity_conflict"
    /// The incoming revision is itself a declared parent that local
    /// revisions were missing — importing it fills a gap mid-history.
    case fillsMissingPredecessor = "fills_missing_predecessor"
    /// The declared parent resolves locally but is not a current head
    /// (it already has a child) — the import creates a parallel
    /// branch.
    case newParallelHead = "new_parallel_head"
    /// The declared parent resolves locally and is a current head —
    /// the import extends a tip.
    case extendsHead = "extends_head"
    /// No parent is declared, the declared parent does not resolve
    /// locally, or the declared parent resolves in a different series —
    /// the import lands as a new root / gapped history.
    case unresolvedPredecessor = "unresolved_predecessor"
}

public extension CaptureSeriesRevisionGraph {
    /// Classifies an incoming bundle's declared lineage against the
    /// pre-import inventory (the candidate is not yet adopted).
    static func classifyImport(
        captureSeriesID: CaptureSeriesID,
        captureRevisionID: CaptureRevisionID,
        parentRevisionID: CaptureRevisionID?,
        allRecords: [PersistedCaptureRecord]
    ) -> ImportLineageClassification {
        if let existing = allRecords.first(where: {
            $0.captureRevisionID == captureRevisionID
        }) {
            let sameLineage =
                existing.captureSeriesID == captureSeriesID
                && existing.parentRevisionID == parentRevisionID
            return sameLineage ? .exactDuplicate : .identityConflict
        }
        // An incoming revision that fills a declared gap takes
        // precedence over how its own parent resolves.
        let fillsGap = allRecords.contains {
            $0.captureSeriesID == captureSeriesID
                && $0.parentRevisionID == captureRevisionID
        }
        if fillsGap {
            return .fillsMissingPredecessor
        }
        guard let parentRevisionID else {
            return .unresolvedPredecessor
        }
        guard let parent = allRecords.first(where: {
            $0.captureRevisionID == parentRevisionID
        }), parent.captureSeriesID == captureSeriesID
        else {
            return .unresolvedPredecessor
        }
        let graph = CaptureSeriesRevisionGraph(
            allRecords: allRecords,
            captureSeriesID: captureSeriesID
        )
        if graph.nodes[parentRevisionID]?.children.isEmpty == false {
            return .newParallelHead
        }
        return .extendsHead
    }
}
