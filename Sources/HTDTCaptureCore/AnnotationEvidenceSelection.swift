import Foundation

/// Issue #207: evidence-reference selection for the manual-annotation
/// flow, split into three disjoint ownership classes so that reverting
/// a captured authority removes exactly the refs that authority
/// exclusively introduced — never refs the user explicitly selected,
/// and never refs still owned by another active authority.
///
/// The previous UI merged authority evidence refs into the same set as
/// user selections, so "use manual position/yaw instead" dropped the
/// authority object while its refs silently stayed attached to the
/// saved annotation. With this type the saved `evidence_refs` always
/// reflect the active authority graph, not the history of UI actions.
public struct AnnotationEvidenceSelection: Sendable, Equatable {
    /// Refs explicitly selected by the user in the evidence selector.
    /// Owned by the user: authority replacement never removes them.
    public var userSelected: Set<String>

    /// Refs introduced by the active placement authority. Owned by
    /// that authority: they are dropped when it is replaced or
    /// reverted to manual.
    public private(set) var placementOwned: Set<String>

    /// Refs introduced by the active orientation authority under the
    /// same ownership rule.
    public private(set) var orientationOwned: Set<String>

    public init(userSelected: Set<String> = []) {
        self.userSelected = userSelected
        self.placementOwned = []
        self.orientationOwned = []
    }

    /// The refs the annotation should carry: the union of every
    /// ownership class, deterministically sorted. A ref survives a
    /// reverted authority while the user still selects it or another
    /// active authority still owns it.
    public var effectiveRefs: [String] {
        userSelected
            .union(placementOwned)
            .union(orientationOwned)
            .sorted()
    }

    /// Installs or clears the placement authority. Refs exclusively
    /// owned by the previous authority are dropped; recapture replaces
    /// the owned set wholesale rather than accumulating stale refs.
    public mutating func replacePlacementAuthority(
        _ authority: AnnotationPlacementAuthority?
    ) {
        placementOwned =
            authority.map { Set($0.evidenceRefs) } ?? []
    }

    /// Installs or clears the orientation authority under the same
    /// exclusive-ownership rule.
    public mutating func replaceOrientationAuthority(
        _ authority: AnnotationOrientationAuthority?
    ) {
        orientationOwned =
            authority.map { Set($0.evidenceRefs) } ?? []
    }
}
