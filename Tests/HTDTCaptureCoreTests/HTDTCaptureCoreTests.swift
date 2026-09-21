import Foundation
import Testing
@testable import HTDTCaptureCore

@Test
func identifierCodableUsesCanonicalLowercaseString() throws {
    let id = CaptureSessionID(
        rawValue: UUID(uuidString: "A0B1C2D3-E4F5-4A67-8B90-1234567890AB")!
    )
    let data = try JSONEncoder().encode(id)
    #expect(String(decoding: data, as: UTF8.self) == "\"a0b1c2d3-e4f5-4a67-8b90-1234567890ab\"")

    let decoded = try JSONDecoder().decode(CaptureSessionID.self, from: data)
    #expect(decoded == id)
}

@Test
func stateMachineHappyPath() throws {
    var machine = CaptureStateMachine()
    try machine.apply(.beginCapabilityCheck)
    try machine.apply(.capabilitiesAccepted)
    try machine.apply(.permissionsGranted)
    try machine.apply(.prepared)
    try machine.apply(.beginReview)
    try machine.apply(.beginAnnotation)
    try machine.apply(.beginValidation)
    try machine.apply(.finalize)
    try machine.apply(.export)
    #expect(machine.state == .exported)
}

@Test
func reviewCanReturnToScanningBeforeAuthorityIsSealed() throws {
    var machine = CaptureStateMachine(state: .reviewing)

    try machine.apply(.resumeScanning)

    #expect(machine.state == .scanning)
    #expect(machine.lastFailure == nil)
}

/// Issue #101: after a Review -> Scanning reopen, the same capture must
/// be able to End again and walk the ordinary authority path — a later
/// Review can still annotate and finalize. No phantom revision or
/// terminal edge is introduced by the round trip.
@Test
func reviewReopenRoundTripKeepsLaterAuthorityTransitions() throws {
    var machine = CaptureStateMachine(state: .scanning)

    try machine.apply(.beginReview)
    try machine.apply(.resumeScanning)
    #expect(machine.state == .scanning)

    try machine.apply(.beginReview)
    #expect(machine.state == .reviewing)

    try machine.apply(.beginAnnotation)
    try machine.apply(.beginReview)
    try machine.apply(.beginValidation)
    try machine.apply(.finalize)
    #expect(machine.state == .finalized)
}

/// Issue #101/#102: the reopen edge exists only while Review is live.
/// Every other state must reject `.resumeScanning` so a reopen cannot
/// be smuggled past annotation, validation, or terminal authority.
@Test
func resumeScanningIsRejectedOutsideReview() {
    for state in CaptureState.allCases where state != .reviewing {
        var machine = CaptureStateMachine(state: state)
        #expect(throws: CaptureStateMachineError.self) {
            try machine.apply(.resumeScanning)
        }
        #expect(machine.state == state)
    }
}

@Test
func finalizedCaptureCanResetWithoutExport() throws {
    var machine = CaptureStateMachine(state: .validating)
    try machine.apply(.finalize)
    #expect(machine.state == .finalized)

    try machine.apply(.reset)
    #expect(machine.state == .idle)
    #expect(machine.lastFailure == nil)
}

@Test
func validationFailureReturnsToReviewForRetry() throws {
    var machine = CaptureStateMachine(state: .reviewing)
    try machine.apply(.beginValidation)
    #expect(machine.state == .validating)

    try machine.apply(.validationFailed)
    #expect(machine.state == .reviewing)
    #expect(machine.lastFailure == nil)
}

@Test
func stateMachineRejectsInvalidTransition() {
    var machine = CaptureStateMachine()
    #expect(throws: CaptureStateMachineError.self) {
        try machine.apply(.finalize)
    }
    #expect(machine.state == .idle)
}

@Test
func failureAndResetAreExplicit() throws {
    var machine = CaptureStateMachine(state: .scanning)
    try machine.apply(.fail(.storagePressure))
    #expect(machine.state == .failed)
    #expect(machine.lastFailure == .storagePressure)
    try machine.apply(.reset)
    #expect(machine.state == .idle)
    #expect(machine.lastFailure == nil)
}

@Test
func unresolvedRoomPlanEndTimeoutIsBoundedAndWarnsFirst() {
    // #96: a lost RoomPlan completion callback must never leave the
    // capture UI locked in `isEndingScan` — the wait has a hard bound
    // and the operator warning is observable before termination.
    let policy = RoomPlanEndTimeoutPolicy()
    #expect(policy.warningDelay == .seconds(8))
    #expect(policy.terminationDelay == .seconds(30))
    #expect(policy.warningDelay < policy.terminationDelay)
    #expect(policy.unresolvedGracePeriod == .seconds(22))
    #expect(policy.unresolvedGracePeriod > .zero)
}

@Test
func unresolvedRoomPlanEndTerminatesFailedNotPseudoScanning() throws {
    // #96: when no correlated RoomPlan completion arrives inside the
    // bounded window the host resolves the attempt as a precise
    // terminal failure — never storage/persistence — and the capture
    // cannot silently return to scanning or reviewing without an
    // explicit reset.
    var machine = CaptureStateMachine(state: .scanning)
    try machine.apply(.fail(.roomPlanFailure))
    #expect(machine.state == .failed)
    #expect(machine.lastFailure == .roomPlanFailure)
    #expect(machine.lastFailure != .persistenceFailure)
    #expect(machine.lastFailure != .storagePressure)

    // From .failed there is no path back into a live capture state:
    // the ended attempt is never left half-live.
    var reviewAttempt = machine
    #expect(throws: CaptureStateMachineError.self) {
        try reviewAttempt.apply(.beginReview)
    }
    var resumeAttempt = machine
    #expect(throws: CaptureStateMachineError.self) {
        try resumeAttempt.apply(.resumeScanning)
    }
    var scanAttempt = machine
    #expect(throws: CaptureStateMachineError.self) {
        try scanAttempt.apply(.prepared)
    }
    #expect(reviewAttempt.state == .failed)
    #expect(resumeAttempt.state == .failed)
    #expect(scanAttempt.state == .failed)

    try machine.apply(.reset)
    #expect(machine.state == .idle)
    #expect(machine.lastFailure == nil)
}

@Test
func coordinateDiscontinuityCreatesNewAuthority() {
    var context = CaptureSessionContext()
    let previous = context.coordinateSpaceID
    let next = context.registerDiscontinuity(
        reason: .worldOriginReset,
        sessionTimestampSeconds: 12.5
    )
    #expect(next != previous)
    #expect(context.coordinateSpaceID == next)
    #expect(context.coordinateTransitions.count == 1)
    #expect(context.coordinateTransitions[0].previous == previous)
    #expect(context.coordinateTransitions[0].next == next)
}

@Test
func capabilityMatrixRequiresPhysicalProbeWhenDepthExists() {
    let capabilities = CaptureCapabilityMatrix(
        roomPlanSupported: true,
        worldTrackingSupported: true,
        sceneReconstructionSupported: true,
        sceneDepthSupported: true
    )
    #expect(capabilities.roomPlanMeshEligible)
    #expect(capabilities.requiresCombinedFeatureProbe)
    #expect(capabilities.allowedModes.contains(.roomPlanMesh))
    #expect(capabilities.allowedModes.contains(.evidenceDepth))
}

@Test
func admissionControllerBoundsPendingEvidence() throws {
    let controller = CaptureStoreAdmissionController(
        maxBytes: 10,
        maxItems: 2
    )

    let first = try controller.reserve(bytes: 6)
    do {
        _ = try controller.reserve(bytes: 5)
        Issue.record("Expected byte limit rejection")
    } catch let error as CaptureStoreAdmissionError {
        #expect(
            error == .byteLimitExceeded(
                requested: 5,
                reserved: 6,
                maxBytes: 10
            )
        )
    }

    try controller.release(first)
    let snapshot = controller.snapshot()
    #expect(snapshot.reservedBytes == 0)
    #expect(snapshot.reservedItems == 0)
}

@Test
func bundleCollisionKeyUsesUnicodeCaseFolding() {
    #expect(
        BundleLogicalPath.collisionKey("straße/payload.bin")
            == BundleLogicalPath.collisionKey(
                "STRASSE/payload.bin"
            )
    )
}

@Test
func bundleCollisionKeyNormalizesNFCBeforeCaseFolding() {
    // #95: an NFD spelling must land on the same NFC + case-fold key
    // as its composed equivalent, matching the Python reference
    // validator's normalize("NFC", path).casefold() authority.
    #expect(
        BundleLogicalPath.collisionKey("E\u{0301}TAGE/payload.bin")
            == "étage/payload.bin"
    )
    #expect(
        BundleLogicalPath.collisionKey("ÉTAGE/payload.bin")
            == "étage/payload.bin"
    )
}

@Test
func storePathRejectsTraversalAndBackslashes() {
    #expect(throws: CaptureStorePathError.self) {
        _ = try CaptureStorePath("../escape")
    }
    #expect(throws: CaptureStorePathError.self) {
        _ = try CaptureStorePath("a\\b")
    }
    #expect(throws: CaptureStorePathError.self) {
        _ = try CaptureStorePath("/absolute")
    }
}

@Test
func depthSurfaceSelectorSeparatesForegroundFromBackground() {
    var samples: [DepthGridSample] = []
    let step = 10

    for y in stride(from: 10, through: 90, by: step) {
        for x in stride(from: 10, through: 90, by: step) {
            let foreground =
                x >= 30 && x <= 70
                    && y >= 30 && y <= 70
            samples.append(
                DepthGridSample(
                    x: x,
                    y: y,
                    depthMeters: foreground ? 1.45 : 3.0
                )
            )
        }
    }

    let selected =
        DepthConnectedSurfaceSelector
            .selectForegroundConnectedComponent(
                samples: samples,
                imageWidth: 101,
                imageHeight: 101,
                gridStepPixels: step,
                minimumComponentCount: 8
            )

    #expect(selected.count == 25)
    #expect(
        selected.allSatisfy {
            $0.x >= 30 && $0.x <= 70
                && $0.y >= 30 && $0.y <= 70
                && abs($0.depthMeters - 1.45) < 0.001
        }
    )
}

@Test
func depthSurfaceSelectorDoesNotPreferTinyNearClutter() {
    let step = 10
    var samples: [DepthGridSample] = []

    // Substantial centered foreground surface.
    for y in stride(from: 30, through: 70, by: step) {
        for x in stride(from: 30, through: 70, by: step) {
            samples.append(
                DepthGridSample(
                    x: x,
                    y: y,
                    depthMeters: 1.55
                )
            )
        }
    }

    // Smaller nearer component off to one side of the same central window.
    for y in stride(from: 30, through: 60, by: step) {
        for x in stride(from: 10, through: 20, by: step) {
            samples.append(
                DepthGridSample(
                    x: x,
                    y: y,
                    depthMeters: 0.95
                )
            )
        }
    }

    let selected =
        DepthConnectedSurfaceSelector
            .selectForegroundConnectedComponent(
                samples: samples,
                imageWidth: 101,
                imageHeight: 101,
                gridStepPixels: step,
                minimumComponentCount: 8
            )

    #expect(selected.count == 25)
    #expect(
        selected.allSatisfy {
            abs($0.depthMeters - 1.55) < 0.001
        }
    )
}

@Test
func depthSurfaceSelectorKeepsSmoothCurvedDepthContinuity() {
    let step = 8
    var samples: [DepthGridSample] = []

    for y in stride(from: 16, through: 80, by: step) {
        for x in stride(from: 16, through: 80, by: step) {
            let dx = Double(x - 48) / 32
            let dy = Double(y - 48) / 32
            let depth =
                1.6 + 0.08 * (dx * dx + dy * dy)
            samples.append(
                DepthGridSample(
                    x: x,
                    y: y,
                    depthMeters: depth
                )
            )
        }
    }

    let selected =
        DepthConnectedSurfaceSelector
            .selectForegroundConnectedComponent(
                samples: samples,
                imageWidth: 96,
                imageHeight: 96,
                gridStepPixels: step,
                minimumComponentCount: 8
            )

    #expect(selected.count == samples.count)
}

@Test
func atomicWriterAllowsOnlyByteIdenticalReplay() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let writer = try AtomicCaptureFileWriter(rootDirectory: root)
    let path = try CaptureStorePath("session/replay.bin")
    let payload = Data([1, 2, 3, 4])

    try await writer.writeIfIdentical(payload, to: path)
    try await writer.writeIfIdentical(payload, to: path)

    await #expect(throws: CaptureFileWriterError.self) {
        try await writer.writeIfIdentical(
            Data([9, 9, 9]),
            to: path
        )
    }

    let stored = try Data(
        contentsOf:
            root.appendingPathComponent("session/replay.bin")
    )
    #expect(stored == payload)
}

@Test
func atomicWriterDoesNotOverwriteEvidence() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let writer = try AtomicCaptureFileWriter(rootDirectory: root)
    let path = try CaptureStorePath("session/test.bin")
    try await writer.write(Data([1, 2, 3]), to: path)

    #expect(
        FileManager.default.fileExists(
            atPath: root.appendingPathComponent("session/test.bin").path
        )
    )

    await #expect(throws: CaptureFileWriterError.self) {
        try await writer.write(Data([4]), to: path)
    }
}
