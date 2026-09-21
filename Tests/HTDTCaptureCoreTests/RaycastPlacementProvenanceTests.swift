import Foundation
import Testing
@testable import HTDTCaptureCore

// #173: raycast placements retain the hit target and result provenance
// so existing-plane and estimated-plane hits stay distinguishable.

@Test
func raycastProvenanceRoundTrips() throws {
    let anchorID = UUID(
        uuidString: "30000000-0000-4000-8000-0000000000aa"
    )!
    let hitTransform = try Matrix4x4F(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0.25, -0.5, 1.5, 1,
    ])
    let raycast = try RaycastPlacementProvenance(
        targetType: "existing_plane_geometry",
        hitDistanceMeters: 1.75,
        hitAnchorIdentifier: anchorID,
        hitTransform: hitTransform
    )
    let placement = try PlacementProvenance(
        method: .raycast,
        sourceEvidenceRefs: ["path:evidence/frames/a.json"],
        raycast: raycast
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(placement)
    let decoded = try JSONDecoder().decode(
        PlacementProvenance.self,
        from: data
    )
    #expect(decoded == placement)
    #expect(decoded.raycast?.targetType == "existing_plane_geometry")
    #expect(decoded.raycast?.hitDistanceMeters == 1.75)
    #expect(decoded.raycast?.hitAnchorIdentifier == anchorID)
    #expect(decoded.raycast?.hitTransform == hitTransform)
}

@Test
func estimatedPlaneStaysDistinguishableFromExistingPlane() throws {
    let existing = try RaycastPlacementProvenance(
        targetType: "existing_plane_geometry",
        hitDistanceMeters: 1.0
    )
    let estimated = try RaycastPlacementProvenance(
        targetType: "estimated_plane",
        hitDistanceMeters: 1.0
    )
    #expect(existing.targetType != estimated.targetType)
}

@Test
func raycastProvenanceRequiresRaycastMethod() throws {
    let raycast = try RaycastPlacementProvenance(
        targetType: "estimated_plane"
    )
    #expect(throws: AnnotationModelError.invalidPlacementReference) {
        _ = try PlacementProvenance(
            method: .manualNumeric,
            raycast: raycast
        )
    }
    #expect(throws: AnnotationModelError.invalidPlacementReference) {
        _ = try PlacementProvenance(
            method: .meshHitTest,
            sourceMeshAnchorID: UUID(
                uuidString: "30000000-0000-4000-8000-0000000000bb"
            )!,
            raycast: raycast
        )
    }
}

@Test
func raycastProvenanceValidatesFields() {
    #expect(throws: AnnotationModelError.invalidPlacementReference) {
        _ = try RaycastPlacementProvenance(targetType: "")
    }
    #expect(throws: AnnotationModelError.invalidPlacementReference) {
        _ = try RaycastPlacementProvenance(
            targetType: "estimated_plane",
            hitDistanceMeters: -1
        )
    }
    #expect(throws: AnnotationModelError.invalidPlacementReference) {
        _ = try RaycastPlacementProvenance(
            targetType: "estimated_plane",
            hitDistanceMeters: .nan
        )
    }
}

@Test
func absentRaycastProvenanceDecodesAsNil() throws {
    // Additive decoding: payloads written before the field existed
    // remain readable.
    let json = """
        {"method":"manual_numeric","source_evidence_refs":[],\
        "source_mesh_anchor_id":null,"source_roomplan_object_id":null,\
        "source_semantic_entity_id":null}
        """
    let decoded = try JSONDecoder().decode(
        PlacementProvenance.self,
        from: Data(json.utf8)
    )
    #expect(decoded.method == .manualNumeric)
    #expect(decoded.raycast == nil)
}

@Test
func minimalOptionalFieldsRemainExplicitlyAbsent() throws {
    let raycast = try RaycastPlacementProvenance(
        targetType: "estimated_plane"
    )
    #expect(raycast.hitDistanceMeters == nil)
    #expect(raycast.hitAnchorIdentifier == nil)
    #expect(raycast.hitTransform == nil)
}
