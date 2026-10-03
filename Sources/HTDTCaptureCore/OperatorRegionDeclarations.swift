import Foundation

/// Operator-declared coverage exceptions (legacy bolph71656-ai/HTDT-Capture#257).
///
/// Real rooms contain regions the operator deliberately cannot
/// resolve — behind fixed cabinets, unsafe areas, intentionally
/// out-of-scope. A declaration marks the bounded coverage cell as
/// "unresolved on purpose": guidance stops requesting it, but the
/// region is never reported as observed, and the reason survives
/// Review/finalization as advisory provenance.
public enum DeclaredRegionReason: String, Codable, Sendable, CaseIterable {
    case inaccessible
    case occludedFixedObject = "occluded_fixed_object"
    case unsafe
    case outOfScope = "out_of_scope"
}

public struct DeclaredCoverageRegion: Sendable, Equatable {
    public let key: SpatialCoverageCellKey
    public let reason: DeclaredRegionReason
    public let declaredAtSessionSeconds: Double

    public init(
        key: SpatialCoverageCellKey,
        reason: DeclaredRegionReason,
        declaredAtSessionSeconds: Double
    ) {
        self.key = key
        self.reason = reason
        self.declaredAtSessionSeconds = declaredAtSessionSeconds
    }
}

/// Bounded set of live declarations for one scan. Reversible until
/// finalization; persisted by the host through the advisory channel.
public struct OperatorRegionDeclarations: Sendable, Equatable {
    public static let maximumDeclarations = 32

    public private(set) var regions: [DeclaredCoverageRegion] = []

    public init() {}

    public var declaredKeys: Set<SpatialCoverageCellKey> {
        Set(regions.map(\.key))
    }

    @discardableResult
    public mutating func declare(
        _ region: DeclaredCoverageRegion
    ) -> Bool {
        if let existing = regions.firstIndex(where: {
            $0.key == region.key
        }) {
            regions[existing] = region
            return true
        }
        guard regions.count < Self.maximumDeclarations else {
            return false
        }
        regions.append(region)
        return true
    }

    @discardableResult
    public mutating func revoke(
        key: SpatialCoverageCellKey
    ) -> Bool {
        let before = regions.count
        regions.removeAll { $0.key == key }
        return regions.count != before
    }

    public func region(at key: SpatialCoverageCellKey) -> DeclaredCoverageRegion? {
        regions.first { $0.key == key }
    }
}
