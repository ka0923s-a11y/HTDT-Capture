import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Issue bolph71656-ai/HTDT-Capture#376: the pre-finalization evidence contact sheet — tiles
/// ordered by capture time, filters/sorts, removal assessment, and
/// the privacy flag channel.
final class EvidenceContactSheetTests: XCTestCase {
    private let sessionID = CaptureSessionID(
        rawValue: UUID(
            uuidString: "30000000-0000-4000-8000-000000000003"
        )!
    )
    private let spaceID = CoordinateSpaceID(
        rawValue: UUID(
            uuidString: "30000000-0000-4000-8000-000000000004"
        )!
    )

    private func sha(_ seed: UInt8) throws -> EvidenceSHA256 {
        try EvidenceSHA256(
            String(repeating: String(format: "%02x", seed), count: 32)
        )
    }

    private func evidenceItem(
        timestamp: Double,
        bytes: Int64 = 1000,
        referencedBy: [String] = [],
        retentionReason: EvidenceRetentionReason =
            .operatorSaved,
        removable: Bool = true
    ) throws -> ReviewEvidenceItem {
        let frameID = EvidenceFrameID()
        return ReviewEvidenceItem(
            frameID: frameID,
            descriptorPath:
                "evidence/frames/\(frameID.description).json",
            pixelPath:
                "evidence/frames/\(frameID.description).pixelbin",
            previewPath: nil,
            previewFileURL: nil,
            byteCount: bytes,
            sessionTimestampSeconds: timestamp,
            coordinateSpaceID: spaceID,
            referencedBy: referencedBy,
            retentionReason: retentionReason,
            removable: removable
        )
    }

    private func descriptor(
        frameID: EvidenceFrameID,
        timestamp: Double,
        depthStatus: FrameDepthStatus = .notRequested,
        depth: DepthEvidenceReference? = nil
    ) throws -> FrameEvidenceDescriptor {
        try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: sessionID,
            coordinateSpaceID: spaceID,
            sessionTimestampSeconds: timestamp,
            worldFromCamera: Matrix4x4F.identity,
            intrinsics: try CameraIntrinsics3x3(
                values: [
                    1500, 0, 0,
                    0, 1500, 0,
                    960, 540, 1,
                ]
            ),
            imageWidth: 1920,
            imageHeight: 1080,
            pixelFormatFourCC: 0x42475241,
            pixelRelativePath:
                "evidence/frames/\(frameID.description).pixelbin",
            pixelByteCount: 100,
            pixelSHA256: sha(7),
            depthStatus: depthStatus,
            depth: depth
        )
    }

    func testCaptureOrderFollowsTimestamp() throws {
        let later = try evidenceItem(timestamp: 20)
        let earlier = try evidenceItem(timestamp: 5)
        let model = EvidenceContactSheetModel(
            evidenceItems: [later, earlier],
            descriptors: [],
            advisoryNotes: []
        )
        XCTAssertEqual(
            model.items.map(\.item.frameID),
            [earlier.frameID, later.frameID]
        )
        XCTAssertEqual(model.items[0].captureOrder, 0)
        XCTAssertEqual(model.items[1].captureOrder, 1)
    }

    func testDepthSummaryMapsDescriptorStatus() throws {
        let noDepth = try evidenceItem(timestamp: 1)
        let smoothed = try evidenceItem(timestamp: 2)
        let model = EvidenceContactSheetModel(
            evidenceItems: [noDepth, smoothed],
            descriptors: [
                try descriptor(
                    frameID: noDepth.frameID,
                    timestamp: 1,
                    depthStatus: .unavailable
                ),
                try descriptor(
                    frameID: smoothed.frameID,
                    timestamp: 2,
                    depthStatus: .capturedSmoothed,
                    depth: try DepthEvidenceReference(
                        kind: .smoothedSceneDepth,
                        depthRelativePath:
                            "evidence/frames/d.depthbin",
                        depthByteCount: 10,
                        depthSHA256: sha(8)
                    )
                ),
            ],
            advisoryNotes: []
        )
        XCTAssertEqual(
            model.items[0].depthSummary, .unavailable
        )
        XCTAssertEqual(
            model.items[1].depthSummary,
            .smoothed(hasConfidence: false)
        )
        XCTAssertTrue(model.items[1].depthSummary.hasDepth)
        XCTAssertFalse(model.items[0].depthSummary.hasDepth)
    }

    func testUsabilityAndPrivacyFromAdvisoryNotes() throws {
        let flagged = try evidenceItem(timestamp: 1)
        let privacy = try evidenceItem(timestamp: 2)
        let clean = try evidenceItem(timestamp: 3)
        let model = EvidenceContactSheetModel(
            evidenceItems: [flagged, privacy, clean],
            descriptors: [],
            advisoryNotes: [
                CaptureAdvisoryNote(
                    kind: .frameUsability,
                    sessionTimestampSeconds: 1,
                    detail:
                        "frame=\(flagged.frameID.description) status=usable_with_issues issues=too_dark"
                ),
                CaptureAdvisoryNote(
                    kind: .privacyFlag,
                    sessionTimestampSeconds: 2,
                    detail: "frame=\(privacy.frameID.description)"
                ),
            ]
        )
        XCTAssertTrue(model.items[0].hasUsabilityWarning)
        XCTAssertEqual(
            model.items[0].usabilityIssues, [.tooDark]
        )
        XCTAssertTrue(model.items[1].privacyFlagged)
        XCTAssertFalse(model.items[2].hasUsabilityWarning)
        XCTAssertFalse(model.items[2].privacyFlagged)
    }

    /// legacy bolph71656-ai/HTDT-Capture#460: a `privacy_flag_cleared` note recorded after the flag
    /// lifts it again — the paired revocation of the advisory flag.
    func testPrivacyFlagClearedByPairedNote() throws {
        let item = try evidenceItem(timestamp: 1)
        let model = EvidenceContactSheetModel(
            evidenceItems: [item],
            descriptors: [],
            advisoryNotes: [
                CaptureAdvisoryNote(
                    kind: .privacyFlag,
                    sessionTimestampSeconds: 2,
                    detail: "frame=\(item.frameID.description)"
                ),
                CaptureAdvisoryNote(
                    kind: .privacyFlagCleared,
                    sessionTimestampSeconds: 3,
                    detail: "frame=\(item.frameID.description)"
                ),
            ]
        )
        XCTAssertFalse(model.items[0].privacyFlagged)

        // A flag recorded after the clear re-raises it — notes
        // replay in capture order, last action wins.
        let reflagged = EvidenceContactSheetModel(
            evidenceItems: [item],
            descriptors: [],
            advisoryNotes: [
                CaptureAdvisoryNote(
                    kind: .privacyFlagCleared,
                    sessionTimestampSeconds: 3,
                    detail: "frame=\(item.frameID.description)"
                ),
                CaptureAdvisoryNote(
                    kind: .privacyFlag,
                    sessionTimestampSeconds: 4,
                    detail: "frame=\(item.frameID.description)"
                ),
            ]
        )
        XCTAssertTrue(reflagged.items[0].privacyFlagged)
    }

    func testFiltersAndSorts() throws {
        let referenced = try evidenceItem(
            timestamp: 1,
            referencedBy: ["entity:speaker"]
        )
        let unreferenced = try evidenceItem(timestamp: 2)
        let flagged = try evidenceItem(timestamp: 3)
        let model = EvidenceContactSheetModel(
            evidenceItems: [referenced, unreferenced, flagged],
            descriptors: [],
            advisoryNotes: [
                CaptureAdvisoryNote(
                    kind: .frameUsability,
                    sessionTimestampSeconds: 3,
                    detail:
                        "frame=\(flagged.frameID.description) status=suspect"
                ),
            ]
        )
        XCTAssertEqual(
            model.items(matching: .referenced).map(\.item.frameID),
            [referenced.frameID]
        )
        XCTAssertEqual(
            model.items(matching: .unreferenced)
                .map(\.item.frameID),
            [unreferenced.frameID, flagged.frameID]
        )
        XCTAssertEqual(
            model.items(matching: .warnings).map(\.item.frameID),
            [flagged.frameID]
        )
        XCTAssertEqual(
            model.items(matching: .privacyFlagged)
                .map(\.item.frameID),
            []
        )
        XCTAssertEqual(
            model.items(
                matching: .all,
                sortedBy: .referenceCount
            ).map(\.item.frameID).first,
            referenced.frameID
        )
    }

    func testAutomaticKeyframeFilter() throws {
        let keyframe = try evidenceItem(
            timestamp: 1,
            retentionReason: .automaticKeyframe
        )
        let manual = try evidenceItem(timestamp: 2)
        let model = EvidenceContactSheetModel(
            evidenceItems: [keyframe, manual],
            descriptors: [],
            advisoryNotes: []
        )
        XCTAssertEqual(
            model.items(matching: .automaticKeyframes)
                .map(\.item.frameID),
            [keyframe.frameID]
        )
    }

    func testRemovalAssessmentClassification() throws {
        let endBoundary = try evidenceItem(
            timestamp: 1,
            retentionReason: .endBoundary,
            removable: false
        )
        let referenced = try evidenceItem(
            timestamp: 2,
            referencedBy: [
                "entity:speaker", "measurement:width",
            ],
            retentionReason: .linkedToAuthority,
            removable: false
        )
        let free = try evidenceItem(timestamp: 3)
        let model = EvidenceContactSheetModel(
            evidenceItems: [endBoundary, referenced, free],
            descriptors: [],
            advisoryNotes: []
        )
        XCTAssertEqual(
            model.removalAssessment(for: endBoundary.frameID),
            .endBoundaryEvidence
        )
        XCTAssertEqual(
            model.removalAssessment(for: referenced.frameID),
            .blockedByDependents([
                "entity:speaker", "measurement:width",
            ])
        )
        XCTAssertEqual(
            model.removalAssessment(for: free.frameID),
            .removable
        )
        // A frame absent from the sheet is read-only, never
        // removable.
        XCTAssertEqual(
            model.removalAssessment(for: EvidenceFrameID()),
            .readOnlyBundle
        )
    }

    func testRemovalPlanPartitionsAndReclaims() throws {
        let blocked = try evidenceItem(
            timestamp: 1,
            bytes: 2000,
            referencedBy: ["entity:speaker"],
            retentionReason: .linkedToAuthority,
            removable: false
        )
        let freeA = try evidenceItem(timestamp: 2, bytes: 500)
        let freeB = try evidenceItem(timestamp: 3, bytes: 700)
        let model = EvidenceContactSheetModel(
            evidenceItems: [blocked, freeA, freeB],
            descriptors: [],
            advisoryNotes: []
        )
        let plan = model.removalPlan(
            for: [blocked.frameID, freeA.frameID, freeB.frameID]
        )
        XCTAssertEqual(
            Set(plan.removable),
            [freeA.frameID, freeB.frameID]
        )
        XCTAssertEqual(plan.blocked.count, 1)
        XCTAssertEqual(plan.blocked[0].frameID, blocked.frameID)
        XCTAssertEqual(
            plan.blocked[0].dependents, ["entity:speaker"]
        )
        XCTAssertEqual(plan.reclaimableBytes, 1200)
        XCTAssertEqual(model.totalRetainedBytes, 3200)
        XCTAssertEqual(
            model.bytes(for: [freeA.frameID, freeB.frameID]),
            1200
        )
    }

    func testReadOnlyBundleBlocksEverything() throws {
        let item = try evidenceItem(timestamp: 1)
        let model = EvidenceContactSheetModel(
            evidenceItems: [item],
            descriptors: [],
            advisoryNotes: [],
            readOnly: true
        )
        XCTAssertEqual(
            model.removalAssessment(for: item.frameID),
            .readOnlyBundle
        )
    }
}
