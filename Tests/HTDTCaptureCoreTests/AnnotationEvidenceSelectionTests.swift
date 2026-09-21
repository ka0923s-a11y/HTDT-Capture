import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue #207: reverting a captured placement/orientation authority
/// back to manual must remove exactly the evidence refs that the
/// authority exclusively introduced — user-selected refs and refs
/// still owned by another active authority are retained, and the
/// saved `evidence_refs` reflect the active authority graph rather
/// than the history of UI actions.
final class AnnotationEvidenceSelectionTests: XCTestCase {
    private func placementAuthority(
        refs: [String]
    ) throws -> AnnotationPlacementAuthority {
        try AnnotationPlacementAuthority(
            worldFromAnnotation: .identity,
            placement: PlacementProvenance(
                method: .raycast,
                sourceEvidenceRefs: refs
            ),
            coordinateSpaceID: CoordinateSpaceID(),
            evidenceRefs: refs
        )
    }

    private func orientationAuthority(
        refs: [String]
    ) throws -> AnnotationOrientationAuthority {
        try AnnotationOrientationAuthority(
            orientation: OrientationAxes(
                frontAxisLocal: .unit(0, 0, -1),
                upAxisLocal: .unit(0, 1, 0)
            ),
            coordinateSpaceID: CoordinateSpaceID(),
            evidenceRefs: refs
        )
    }

    /// Capturing a raycast placement, then reverting to manual
    /// position, drops the refs the authority owned.
    func testRevertingPlacementAuthorityDropsOnlyItsRefs() throws {
        var selection = AnnotationEvidenceSelection(
            userSelected: ["path:evidence/frames/user.json"]
        )
        let authority = try placementAuthority(
            refs: ["path:evidence/frames/raycast.json"]
        )
        selection.replacePlacementAuthority(authority)
        XCTAssertEqual(
            selection.effectiveRefs,
            [
                "path:evidence/frames/raycast.json",
                "path:evidence/frames/user.json",
            ]
        )

        selection.replacePlacementAuthority(nil)
        XCTAssertEqual(
            selection.effectiveRefs,
            ["path:evidence/frames/user.json"]
        )
    }

    /// Capturing a speaker heading, then reverting to manual yaw,
    /// drops the refs the orientation authority owned.
    func testRevertingOrientationAuthorityDropsOnlyItsRefs() throws {
        var selection = AnnotationEvidenceSelection(
            userSelected: ["path:evidence/frames/user.json"]
        )
        let authority = try orientationAuthority(
            refs: ["path:evidence/frames/heading.json"]
        )
        selection.replaceOrientationAuthority(authority)
        XCTAssertEqual(
            selection.effectiveRefs,
            [
                "path:evidence/frames/heading.json",
                "path:evidence/frames/user.json",
            ]
        )

        selection.replaceOrientationAuthority(nil)
        XCTAssertEqual(
            selection.effectiveRefs,
            ["path:evidence/frames/user.json"]
        )
    }

    /// A ref the user explicitly selected survives the authority's
    /// removal even when the authority also claimed it.
    func testUserSelectedRefSurvivesAuthorityRevert() throws {
        let shared = "path:evidence/frames/shared.json"
        var selection = AnnotationEvidenceSelection(
            userSelected: [shared]
        )
        selection.replacePlacementAuthority(
            try placementAuthority(refs: [shared])
        )
        selection.replacePlacementAuthority(nil)
        XCTAssertEqual(selection.effectiveRefs, [shared])
    }

    /// A ref owned by two authorities survives until every owner is
    /// cleared.
    func testSharedRefSurvivesUntilAllOwnersCleared() throws {
        let shared = "path:evidence/frames/shared.json"
        var selection = AnnotationEvidenceSelection()
        selection.replacePlacementAuthority(
            try placementAuthority(refs: [shared])
        )
        selection.replaceOrientationAuthority(
            try orientationAuthority(refs: [shared])
        )

        selection.replacePlacementAuthority(nil)
        XCTAssertEqual(selection.effectiveRefs, [shared])

        selection.replaceOrientationAuthority(nil)
        XCTAssertEqual(selection.effectiveRefs, [])
    }

    /// Recapturing an authority replaces its owned refs wholesale —
    /// refs exclusive to the superseded authority do not linger.
    func testRecaptureReplacesOwnedRefs() throws {
        var selection = AnnotationEvidenceSelection()
        selection.replacePlacementAuthority(
            try placementAuthority(
                refs: ["path:evidence/frames/first.json"]
            )
        )
        selection.replacePlacementAuthority(
            try placementAuthority(
                refs: ["path:evidence/frames/second.json"]
            )
        )
        XCTAssertEqual(
            selection.effectiveRefs,
            ["path:evidence/frames/second.json"]
        )
    }

    /// The saved set equals user selections union every active
    /// authority's owned refs, deterministically sorted.
    func testEffectiveRefsReflectActiveAuthorityGraph() throws {
        var selection = AnnotationEvidenceSelection(
            userSelected: ["user:note"]
        )
        selection.replacePlacementAuthority(
            try placementAuthority(
                refs: ["path:evidence/frames/b.json"]
            )
        )
        selection.replaceOrientationAuthority(
            try orientationAuthority(
                refs: ["path:evidence/frames/a.json"]
            )
        )
        XCTAssertEqual(
            selection.effectiveRefs,
            [
                "path:evidence/frames/a.json",
                "path:evidence/frames/b.json",
                "user:note",
            ]
        )
    }
}
