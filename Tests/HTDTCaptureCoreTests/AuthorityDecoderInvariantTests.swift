import Foundation
import Testing
@testable import HTDTCaptureCore

// #150: synthesized decoding must not bypass validating initializers.
// These fixtures mutate otherwise-valid producer JSON so each
// cross-field invariant is exercised through the decode path.

private func decodeEntity(
    _ mutate: (inout [String: Any]) -> Void
) throws -> CaptureAnnotationEntity {
    let entity = try CaptureAnnotationEntity(
        type: .speaker,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Center",
        verificationState: .evidenceLinked,
        placement: PlacementProvenance(
            method: .raycast,
            sourceEvidenceRefs: ["path:evidence/frames/a.json"]
        ),
        orientation: OrientationAxes(
            frontAxisLocal: SpatialVector3F.unit(0, 0, -1),
            upAxisLocal: SpatialVector3F.unit(0, 1, 0)
        ),
        channelRole: .center,
        evidenceRefs: ["path:evidence/frames/a.json"]
    )
    let data = try JSONEncoder().encode(entity)
    var json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    mutate(&json)
    let mutated = try JSONSerialization.data(withJSONObject: json)
    return try JSONDecoder().decode(
        CaptureAnnotationEntity.self,
        from: mutated
    )
}

@Test
func speakerDecodeAllowsAimUnknownAndKeepsRoleContract() throws {
    // #228: nil orientation is a first-class "aim unknown" record —
    // decode keeps it rather than rejecting the entity.
    let unaimed = try decodeEntity { $0["orientation"] = NSNull() }
    #expect(unaimed.orientation == nil)
    #expect(unaimed.channelRole == .center)
    // #315: a missing channel_role decodes as a valid unbound
    // speaker — never replaced by a placeholder token.
    let unbound = try decodeEntity { $0["channel_role"] = NSNull() }
    #expect(unbound.channelRole == nil)
    #expect(unbound.roleBinding == nil)
}

@Test
func decodeRejectsEmptyLabelAndDuplicateRefs() throws {
    #expect(throws: AnnotationModelError.emptyLabel) {
        _ = try decodeEntity { $0["label"] = "" }
    }
    #expect(throws: AnnotationModelError.duplicateEvidenceReference) {
        _ = try decodeEntity {
            $0["evidence_refs"] = ["path:a", "path:a"]
        }
    }
}

@Test
func decodeRejectsEvidenceLinkedWithoutRefs() throws {
    #expect(throws: AnnotationModelError.missingEvidenceLink) {
        _ = try decodeEntity {
            $0["evidence_refs"] = [String]()
            $0["placement"] = [
                "method": "manual_numeric",
                "source_evidence_refs": [String](),
            ]
        }
    }
}

@Test
func decodeNormalizesLabelToNFC() throws {
    let decoded = try decodeEntity {
        $0["label"] = "Cafe\u{0301}"
    }
    #expect(decoded.label == "Caf\u{00E9}")
}

@Test
func decodeRejectsNonOrthogonalAxes() throws {
    #expect(throws: AnnotationModelError.nonOrthogonalAxes) {
        _ = try decodeEntity {
            $0["orientation"] = [
                "front_axis_local": [0.0, 0.0, -1.0],
                "up_axis_local": [0.0, 0.0, -1.0],
            ]
        }
    }
}

@Test
func decodeRejectsRaycastPlacementWithoutSource() throws {
    #expect(throws: AnnotationModelError.invalidPlacementReference) {
        _ = try decodeEntity {
            $0["placement"] = [
                "method": "raycast",
                "source_evidence_refs": [String](),
            ]
        }
    }
}

private func decodeMeasurement(
    _ mutate: (inout [String: Any]) -> Void
) throws -> CaptureMeasurement {
    let measurement = try CaptureMeasurement(
        quantityType: "room_width",
        value: .scalar(3.4),
        unit: .meter,
        acquisitionMethod: .laserDistanceMeter,
        observedAtUTC: "2026-09-20T01:00:00Z",
        userAttestation: .attested,
        provenanceClass: .userAttestedMeasurement,
        evidenceRefs: ["path:evidence/frames/a.json"]
    )
    let data = try JSONEncoder().encode(measurement)
    var json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    mutate(&json)
    let mutated = try JSONSerialization.data(withJSONObject: json)
    return try JSONDecoder().decode(
        CaptureMeasurement.self,
        from: mutated
    )
}

@Test
func measurementDecodeRejectsInvalidTimestamps() throws {
    #expect(throws: MeasurementModelError.invalidObservedTimestamp) {
        _ = try decodeMeasurement { $0["observed_at"] = "yesterday" }
    }
    #expect(throws: MeasurementModelError.invalidObservedTimestamp) {
        _ = try decodeMeasurement {
            $0["observed_at"] = "2026-09-20T01:00:00+02:00"
        }
    }
}

@Test
func measurementDecodeRejectsDerivedUserAttested() throws {
    #expect(
        throws: MeasurementModelError.derivedAcquisitionNotUserAttestable
    ) {
        _ = try decodeMeasurement {
            $0["acquisition_method"] = "lidar_derived"
        }
    }
}

@Test
func measurementDecodeRejectsBadCalibrationDate() throws {
    #expect(throws: MeasurementModelError.invalidCalibrationDate) {
        _ = try decodeMeasurement {
            $0["instrument"] = ["calibration_date": "soon"]
        }
    }
}

@Test
func spatialMeasurementDecodeRequiresCoordinateAuthority() throws {
    #expect(
        throws: MeasurementModelError.missingSpatialCoordinateAuthority
    ) {
        _ = try decodeMeasurement {
            $0["value"] = [1.0, 2.0, 3.0]
        }
    }
}

@Test
func collectionDecodeRejectsDuplicateIDs() throws {
    let entity = try CaptureAnnotationEntity(
        entityID: AnnotationEntityID(
            rawValue: UUID(
                uuidString: "30000000-0000-4000-8000-000000000042"
            )!
        ),
        type: .seat,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .seatReferencePoint,
        label: "Seat",
        placement: PlacementProvenance(method: .manualNumeric)
    )
    let collection = try CaptureAnnotationCollection(
        entities: [entity]
    )
    let data = try JSONEncoder().encode(collection)
    var json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let entities = try #require(json["entities"] as? [[String: Any]])
    json["entities"] = [entities[0], entities[0]]

    let mutated = try JSONSerialization.data(withJSONObject: json)
    #expect(throws: AnnotationModelError.duplicateEntityID) {
        _ = try JSONDecoder().decode(
            CaptureAnnotationCollection.self,
            from: mutated
        )
    }
}

@Test
func collectionDecodeRejectsForeignSchema() throws {
    let collection = try CaptureAnnotationCollection(entities: [])
    let data = try JSONEncoder().encode(collection)
    var json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    json["schema"] = "htdt.other"
    let mutated = try JSONSerialization.data(withJSONObject: json)
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(
            CaptureAnnotationCollection.self,
            from: mutated
        )
    }
}

@Test
func timingDocumentDecodeEnforcesCorrelationOrder() throws {
    let json = """
        {"schema":"htdt.capture.timing","schema_version":"1.0.0",\
        "clock_domain":"arkit_arframe_timestamp_seconds","correlations":[\
        {"monotonic_s":5.0,"utc":"2026-09-20T01:00:05Z","method":"m"},\
        {"monotonic_s":1.0,"utc":"2026-09-20T01:00:01Z","method":"m"}]}
        """
    #expect(
        throws: CaptureSessionMetadataError.invalidCorrelationOrder
    ) {
        _ = try JSONDecoder().decode(
            CaptureTimingDocument.self,
            from: Data(json.utf8)
        )
    }
}

@Test
func timingCorrelationDecodeRejectsNonCanonicalUTC() {
    let json = """
        {"monotonic_s":1.0,"utc":"2026-09-20 01:00:00","method":"m",\
        "estimated_uncertainty_s":null}
        """
    #expect(throws: CaptureSessionMetadataError.invalidUTCTimestamp) {
        _ = try JSONDecoder().decode(
            CaptureTimingCorrelation.self,
            from: Data(json.utf8)
        )
    }
}

@Test
func depthPayloadDecodeEnforcesSampleCount() {
    let json = """
        {"width":4,"height":4,"valuesMeters":[1.0,2.0,3.0],\
        "validityMask":null}
        """
    #expect(throws: DepthEvidenceError.self) {
        _ = try JSONDecoder().decode(
            DepthMapPayload.self,
            from: Data(json.utf8)
        )
    }
}

@Test
func frameDescriptorDecodeEnforcesDepthStatusMatch() throws {
    let hash = try EvidenceSHA256(
        String(repeating: "cd", count: 32)
    )
    let descriptor = try FrameEvidenceDescriptor(
        captureSessionID: CaptureSessionID(),
        coordinateSpaceID: CoordinateSpaceID(),
        sessionTimestampSeconds: 1.0,
        worldFromCamera: .identity,
        intrinsics: CameraIntrinsics3x3(values: [
            1450, 0, 0,
            0, 1450, 0,
            960, 720, 1,
        ]),
        imageWidth: 1920,
        imageHeight: 1440,
        pixelFormatFourCC: 0x34323066,
        pixelRelativePath: "evidence/frames/x.pixelbin",
        pixelByteCount: 32,
        pixelSHA256: hash
    )
    let data = try JSONEncoder().encode(descriptor)
    var json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    // Claim captured depth without a depth reference.
    json["depth_status"] = "captured_scene_depth"
    let mutated = try JSONSerialization.data(withJSONObject: json)
    #expect(
        throws: FrameEvidenceDescriptorError.depthStatusMismatch
    ) {
        _ = try JSONDecoder().decode(
            FrameEvidenceDescriptor.self,
            from: mutated
        )
    }
}

@Test
func frameDescriptorDecodeRejectsNonRigidPose() throws {
    let hash = try EvidenceSHA256(
        String(repeating: "cd", count: 32)
    )
    let descriptor = try FrameEvidenceDescriptor(
        captureSessionID: CaptureSessionID(),
        coordinateSpaceID: CoordinateSpaceID(),
        sessionTimestampSeconds: 1.0,
        worldFromCamera: .identity,
        intrinsics: CameraIntrinsics3x3(values: [
            1450, 0, 0,
            0, 1450, 0,
            960, 720, 1,
        ]),
        imageWidth: 1920,
        imageHeight: 1440,
        pixelFormatFourCC: 0x34323066,
        pixelRelativePath: "evidence/frames/x.pixelbin",
        pixelByteCount: 32,
        pixelSHA256: hash
    )
    let data = try JSONEncoder().encode(descriptor)
    var json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    json["T_world_from_camera"] = [
        "representation": "column_major_4x4_f32",
        "values": [
            2.0, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ],
    ]
    let mutated = try JSONSerialization.data(withJSONObject: json)
    #expect(throws: Matrix4x4FError.nonOrthonormalBasis) {
        _ = try JSONDecoder().decode(
            FrameEvidenceDescriptor.self,
            from: mutated
        )
    }
}

@Test
func validProducerOutputRoundTripsExactly() throws {
    let entity = try CaptureAnnotationEntity(
        type: .speaker,
        coordinateSpaceID: CoordinateSpaceID(),
        worldFromAnnotation: .identity,
        referencePointSemantics: .cabinetReferencePoint,
        label: "Front Left",
        verificationState: .evidenceLinked,
        placement: PlacementProvenance(
            method: .raycast,
            sourceEvidenceRefs: ["path:evidence/frames/a.json"]
        ),
        orientation: OrientationAxes(
            frontAxisLocal: SpatialVector3F.unit(0, 0, -1),
            upAxisLocal: SpatialVector3F.unit(0, 1, 0)
        ),
        channelRole: .left,
        evidenceRefs: ["path:evidence/frames/a.json"]
    )
    let collection = try CaptureAnnotationCollection(entities: [entity])
    let data = try JSONEncoder().encode(collection)
    #expect(
        try JSONDecoder().decode(
            CaptureAnnotationCollection.self,
            from: data
        ) == collection
    )
}
