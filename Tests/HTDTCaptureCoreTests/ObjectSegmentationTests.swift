import Foundation
import Testing
@testable import HTDTCaptureCore

private func makeTemporaryDirectory() throws -> URL {
    try BundleValidationFixture.makeDirectory()
}

// MARK: - View -> image mapping authority

/// The mapping chain an operator tap/box/scribble follows: view-normalized
/// (top-left) -> inverse ARKit display transform -> image-normalized
/// (top-left of `capturedImage`) -> Vision normalized (bottom-left).
/// These fixtures model the aspect-fill display transforms ARKit emits
/// for a 1920x1440 camera image presented in each supported
/// orientation — the correctness anchor of legacy bolph71656-ai/HTDT-Capture#269's "explicit authority".

/// Image space is wider than the view in portrait: the display
/// transform is a rotation-free scale+crop (the horizontal band
/// outside the view is cropped away), exercised as a rotation-90
/// case below for the rotated authorities.
private let portraitTransform = NormalizedAffine2D(
    a: 0, b: 1, c: 0.8889, d: 0, tx: 0.05555, ty: 0
)
private let landscapeLeftTransform = NormalizedAffine2D(
    a: 1.3333, b: 0, c: 0, d: 1, tx: -0.1667, ty: 0
)
private let landscapeRightTransform = NormalizedAffine2D(
    a: -1.3333, b: 0, c: 0, d: -1, tx: 1.1667, ty: 1
)

@Test
func viewToImageMappingHoldsAcrossEveryOrientation() throws {
    let authorities: [(String, NormalizedAffine2D)] = [
        ("portrait", portraitTransform),
        ("landscapeLeft", landscapeLeftTransform),
        ("landscapeRight", landscapeRightTransform),
        ("portraitUpsideDown", NormalizedAffine2D(
            a: 0, b: -1, c: -0.8889, d: 0, tx: 0.94445, ty: 1
        )),
    ]
    for (name, transform) in authorities {
        // The view center must always land at the image center for an
        // orthonormal aspect-fill transform — in any orientation.
        let center = try #require(
            SegmentationViewToImageMapping.imageNormalizedPoint(
                fromViewPoint: NormalizedPoint2D(x: 0.5, y: 0.5),
                displayTransform: transform
            ),
            "\(name): center must map"
        )
        #expect(abs(center.x - 0.5) < 0.001, "\(name) center.x")
        #expect(abs(center.y - 0.5) < 0.001, "\(name) center.y")

        // Round-trip: image -> view -> image is identity.
        let probe = NormalizedPoint2D(x: 0.25, y: 0.7)
        let view = transform.applying(to: probe)
        if view.isUnitSquare {
            let back = try #require(
                SegmentationViewToImageMapping
                    .imageNormalizedPoint(
                        fromViewPoint: view,
                        displayTransform: transform
                    ),
                "\(name): round-trip"
            )
            #expect(abs(back.x - probe.x) < 0.0001)
            #expect(abs(back.y - probe.y) < 0.0001)
        }
    }
}

@Test
func viewPointOutsideCameraCoverageIsNotASeed() {
    // A letterboxed transform leaves bands of the view unmapped: a
    // tap inside the top band inverts to a point above the image.
    #expect(
        SegmentationViewToImageMapping.imageNormalizedPoint(
            fromViewPoint: NormalizedPoint2D(x: 0.5, y: 0.01),
            displayTransform: NormalizedAffine2D(
                a: 1, b: 0, c: 0, d: 0.5625, tx: 0, ty: 0.21875
            )
        ) == nil
    )
    // A singular transform (degenerate viewport) yields no mapping.
    #expect(
        SegmentationViewToImageMapping.imageNormalizedPoint(
            fromViewPoint: NormalizedPoint2D(x: 0.5, y: 0.5),
            displayTransform: NormalizedAffine2D(
                a: 0, b: 0, c: 0, d: 0, tx: 0, ty: 0
            )
        ) == nil
    )
}

@Test
func visionPointFlipsToBottomLeftOrigin() throws {
    let topLeft = try #require(
        SegmentationViewToImageMapping.visionPoint(
            fromImagePoint: NormalizedPoint2D(x: 0.1, y: 0.2)
        )
    )
    #expect(abs(topLeft.x - 0.1) < 0.0001)
    #expect(abs(topLeft.y - 0.8) < 0.0001)
    #expect(
        SegmentationViewToImageMapping.visionPoint(
            fromImagePoint: NormalizedPoint2D(x: 1.2, y: 0.5)
        ) == nil
    )
}

@Test
func displayAuthorityTokensStayStable() {
    let vra = SegmentationDisplayAuthority.viewRotationAngle(
        degrees: 90
    )
    #expect(
        vra.revisionToken
            == "authority=view_rotation_angle;degrees=90.0000"
    )
    let combined = SegmentationDisplayAuthority.revisionToken(
        authority: .interfaceOrientation("portrait"),
        viewportWidthPoints: 390,
        viewportHeightPoints: 844
    )
    #expect(
        combined == "arkit_display_transform;"
            + "authority=interface_orientation;orientation=portrait"
            + ";viewport_pt=390.0x844.0"
    )
}

// MARK: - Bounded run policy

@Test
func runPolicyBoundsRefinementAndViewChange() {
    let policy = SegmentationRunPolicy()
    #expect(policy.acceptsRefinement(count: 7))
    #expect(!policy.acceptsRefinement(count: 8))
    #expect(!policy.acceptsRefinement(count: 40))

    #expect(!policy.viewChangeIsMaterial(
        translationMeters: 0.1, yawDegrees: 5
    ))
    #expect(policy.viewChangeIsMaterial(
        translationMeters: 0.4, yawDegrees: 0
    ))
    #expect(policy.viewChangeIsMaterial(
        translationMeters: 0, yawDegrees: 30
    ))
}

// MARK: - Mask grid encoding

@Test
func maskGridBitPacksAndRoundTrips() throws {
    var grid = SegmentationMaskGrid(width: 17, height: 5)
    grid.set(x: 0, y: 0)
    grid.set(x: 16, y: 0)
    grid.set(x: 8, y: 4)
    #expect(grid.setCount == 3)
    #expect(grid.isSet(x: 16, y: 0))
    #expect(!grid.isSet(x: 8, y: 0))
    // Out-of-range reads/writes are safe no-ops/false.
    #expect(!grid.isSet(x: 17, y: 0))
    grid.set(x: 99, y: 99)
    #expect(grid.setCount == 3)

    let decoded = try #require(
        SegmentationMaskGrid(
            width: 17,
            height: 5,
            base64: grid.base64Encoded
        )
    )
    #expect(decoded == grid)
    // A byte count that cannot cover the grid must not decode.
    #expect(
        SegmentationMaskGrid(width: 17, height: 5, bytes: [0]) == nil
    )
    #expect(
        SegmentationMaskGrid(
            width: 17, height: 5, base64: "!!!"
        ) == nil
    )
}

@Test
func maskContainsUsesSharedNormalizedSpace() {
    var grid = SegmentationMaskGrid(width: 8, height: 8)
    grid.set(x: 2, y: 2)
    #expect(grid.contains(
        imageNormalizedX: 2.5 / 8, imageNormalizedY: 2.5 / 8
    ))
    #expect(!grid.contains(
        imageNormalizedX: 7.5 / 8, imageNormalizedY: 7.5 / 8
    ))
    // Depth-pixel convention: cell centers in the same normalized
    // space — a 4x4 depth map's (1,1) cell covers image-normalized
    // (0.375, 0.375), inside the set quadrant only when nearby.
    #expect(!grid.contains(
        depthX: 0, depthY: 0, depthWidth: 4, depthHeight: 4
    ))
    grid.set(x: 3, y: 3)
    #expect(grid.contains(
        depthX: 1, depthY: 1, depthWidth: 4, depthHeight: 4
    ))
}

@Test
func maskDownsampleStaysBoundedAndLosslessInKind() {
    var grid = SegmentationMaskGrid(width: 512, height: 384)
    for y in 100..<200 {
        for x in 100..<200 {
            grid.set(x: x, y: y)
        }
    }
    let small = grid.downsampled(toMaximumDimension: 256)
    #expect(small.width <= 256 && small.height <= 256)
    #expect(small.width == 256 && small.height == 192)
    #expect(small.setCount > 0)
    // Any-set rule: the downsampled block still registers as object.
    #expect(small.contains(imageNormalizedX: 0.3, imageNormalizedY: 0.4))
    // Smaller-than-max grids pass through unchanged.
    let same = small.downsampled(toMaximumDimension: 256)
    #expect(same == small)
}

// MARK: - Asset readiness / interaction honesty

@Test
func assetReadinessAdmitsOnlyReady() {
    #expect(SegmentationAssetReadiness.ready.admitsSegmentation)
    let blocked: [SegmentationAssetReadiness] = [
        .unknown, .unsupported, .notReady, .downloading,
        .failed("x"),
    ]
    for state in blocked {
        #expect(!state.admitsSegmentation)
    }
}

@Test
func unavailableInteractionDefaultsAreClosed() {
    let state = SegmentationInteractionState.unavailable
    #expect(state.phase == .unavailable)
    #expect(state.assetReadiness == .unknown)
    #expect(!state.canRefine)
    #expect(!state.canResegment)
}

// MARK: - Observation record contract

private func validMask() -> SegmentationMaskGrid {
    var grid = SegmentationMaskGrid(width: 16, height: 16)
    for y in 4..<12 {
        for x in 4..<12 {
            grid.set(x: x, y: y)
        }
    }
    return grid
}

private func makeObservation(
    seedKind: SegmentationSeedKind = .point,
    seedPoints: [NormalizedPoint2D] = [
        NormalizedPoint2D(x: 0.5, y: 0.5),
    ],
    seedBox: NormalizedRect2D? = nil,
    refinementCount: Int = 0,
    sessionTimestampSeconds: Double = 12.5,
    maskPayloadBase64: String? = nil,
    downstream3DPointCount: Int = 0
) throws -> ObjectSegmentationObservation {
    try ObjectSegmentationObservation(
        captureSessionID: CaptureSessionID(
            canonicalString: BundleValidationFixture.sessionUUID
        )!,
        coordinateSpaceID: CoordinateSpaceID(
            canonicalString: BundleValidationFixture.spaceUUID
        )!,
        sourceFrameRef:
            "path:evidence/frames/00000000-0000-4000-8000-"
            + "000000000005.json",
        sourceFrameKind: "streamed",
        sessionTimestampSeconds: sessionTimestampSeconds,
        imageWidth: 1920,
        imageHeight: 1440,
        pixelFormatFourCC: 0x00000020,
        viewRotationOrDisplayTransformRevision:
            "arkit_display_transform;authority=interface_orientation;"
            + "orientation=portrait;viewport_pt=390.0x844.0",
        seedKind: seedKind,
        seedPoints: seedPoints,
        seedBox: seedBox,
        refinementCount: refinementCount,
        qualityLevel: "balanced",
        maskWidth: 16,
        maskHeight: 16,
        maskEncoding: "bitpack_msb_rows_base64",
        maskPayloadRef: "inline",
        maskPayloadBase64: maskPayloadBase64 ?? validMask()
            .base64Encoded,
        maskAcceptThreshold: 0.5,
        visionRequest: "GenerateIterativeSegmentationRequest",
        osVersion: "27.0",
        osBuild: "27A5315c",
        appVersion: "0.1.0",
        appBuild: "42",
        downstream3DPointCount: downstream3DPointCount
    )
}

@Test
func observationRecordValidatesSeedGeometry() throws {
    // Point seed needs exactly one point and no box.
    #expect(
        throws: SegmentationPersistenceError.missingSeedGeometry
    ) {
        _ = try makeObservation(seedPoints: [
            NormalizedPoint2D(x: 0.1, y: 0.1),
            NormalizedPoint2D(x: 0.2, y: 0.2),
        ])
    }
    // Box seed requires a non-empty in-bounds rect.
    #expect(
        throws: SegmentationPersistenceError.missingSeedGeometry
    ) {
        _ = try makeObservation(
            seedKind: .box,
            seedPoints: [],
            seedBox: nil
        )
    }
    _ = try makeObservation(
        seedKind: .box,
        seedPoints: [],
        seedBox: NormalizedRect2D(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
    )
    // Scribble seed requires a path (>=2 points).
    #expect(
        throws: SegmentationPersistenceError.missingSeedGeometry
    ) {
        _ = try makeObservation(
            seedKind: .scribble,
            seedPoints: [NormalizedPoint2D(x: 0.5, y: 0.5)]
        )
    }
    _ = try makeObservation(
        seedKind: .scribble,
        seedPoints: [
            NormalizedPoint2D(x: 0.1, y: 0.1),
            NormalizedPoint2D(x: 0.4, y: 0.4),
        ]
    )
}

@Test
func observationRecordRejectsDishonestFields() throws {
    #expect(throws: SegmentationPersistenceError.pointOutsideUnitSquare) {
        _ = try makeObservation(
            seedPoints: [NormalizedPoint2D(x: 1.2, y: 0.5)]
        )
    }
    #expect(
        throws: SegmentationPersistenceError.invalidSessionTimestamp
    ) {
        _ = try makeObservation(sessionTimestampSeconds: -1)
    }
    #expect(throws: SegmentationPersistenceError.invalidMaskEncoding) {
        _ = try makeObservation(maskPayloadBase64: "bm90LWVub3VnaA==")
    }
    #expect(throws: SegmentationPersistenceError.negativePointCount) {
        _ = try makeObservation(downstream3DPointCount: -1)
    }
    #expect(throws: SegmentationPersistenceError.invalidRefinementCount) {
        _ = try makeObservation(refinementCount: -2)
    }
}

@Test
func observationPackageValidatesAgainstPublishedSchema() throws {
    let observation = try makeObservation(
        refinementCount: 2,
        downstream3DPointCount: 41
    )
    let (package, declaration) =
        try ObjectSegmentationObservationPackageBuilder.build(
            observations: [observation],
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: observation.captureSessionID,
            sourcePayloadRefs: [observation.sourceFrameRef]
        )
    #expect(declaration.role == .derived)
    #expect(
        ObjectSegmentationObservationPackage.path
            == "derived/segmentation-observations.json"
    )

    let text = String(decoding: package.data, as: UTF8.self)
    #expect(text.contains("\"seed_kind\":\"point\""))
    #expect(
        text.contains(
            "\"mask_encoding\":\"bitpack_msb_rows_base64\""
        )
    )

    let roundTrip = try JSONDecoder().decode(
        ObjectSegmentationObservationDocument.self,
        from: package.data
    )
    #expect(roundTrip.observations == [observation])

    let root = try makeTemporaryDirectory()
    defer { BundleValidationFixture.remove(root) }
    let pixelData = try BundleValidationFixture.pixelPayload(
        width: 4, height: 3
    )
    let frameUUID = "00000000-0000-4000-8000-000000000005"
    let pixelPath = "evidence/frames/\(frameUUID).pixelbin"
    try BundleValidationFixture.stage(
        root,
        payloads: [
            (
                path: ObjectSegmentationObservationPackage.path,
                data: package.data,
                mediaType: "application/json"
            ),
            (
                path: "evidence/frames/\(frameUUID).json",
                data: try BundleValidationFixture.canonical(
                    BundleValidationFixture.frameDescriptorValue(
                        pixelPath: pixelPath,
                        pixelByteCount: pixelData.count,
                        pixelSHA256: EvidenceIntegrity
                            .sha256(of: pixelData).description,
                        imageWidth: 4,
                        imageHeight: 3,
                        pixelFormatFourCC: 0x3432_3066
                    )
                ),
                mediaType: "application/json"
            ),
            (
                path: pixelPath,
                data: pixelData,
                mediaType: "application/vnd.htdt.pixelbin"
            ),
        ]
    )
    let report = try BundleDirectoryValidator.validate(root: root)
    #expect(report.valid)
}

// MARK: - Depth/mesh gating

@Test
func depthGateProjectsThroughRealIntrinsics() throws {
    // Camera at the origin looking down -Z (identity world-from-camera)
    // with principal point at the image center.
    let pose = try Matrix4x4F(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ])
    let intrinsics = try CameraIntrinsics3x3(values: [
        1000, 0, 0,
        0, 1000, 0,
        960, 720, 1,
    ])
    let center = try #require(
        SegmentationDepthGate.projectedImagePoint(
            worldX: 0, worldY: 0, worldZ: -2,
            worldFromCamera: pose,
            intrinsics: intrinsics
        )
    )
    #expect(abs(center.x - 960) < 0.01)
    #expect(abs(center.y - 720) < 0.01)

    // Behind the camera is never a support point.
    #expect(
        SegmentationDepthGate.projectedImagePoint(
            worldX: 0, worldY: 0, worldZ: 1,
            worldFromCamera: pose,
            intrinsics: intrinsics
        ) == nil
    )

    // maskContains: only projections inside the accepted mask count.
    // Intrinsics pixels are the real image's pixel space (1920x1440);
    // the mask may be a smaller downsampled grid in the same
    // normalized space.
    var mask = SegmentationMaskGrid(width: 192, height: 144)
    for y in 60..<84 {
        for x in 80..<112 {
            mask.set(x: x, y: y)
        }
    }
    #expect(
        SegmentationDepthGate.maskContains(
            mask: mask,
            worldX: 0, worldY: 0, worldZ: -2,
            worldFromCamera: pose,
            intrinsics: intrinsics,
            imageWidth: 1920, imageHeight: 1440
        )
    )
    #expect(
        !SegmentationDepthGate.maskContains(
            mask: mask,
            worldX: 2, worldY: 2, worldZ: -2,
            worldFromCamera: pose,
            intrinsics: intrinsics,
            imageWidth: 1920, imageHeight: 1440
        )
    )
}
