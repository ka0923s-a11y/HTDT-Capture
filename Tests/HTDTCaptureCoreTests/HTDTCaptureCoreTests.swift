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
func admissionControllerBoundsPendingEvidence() async throws {
    let controller = CaptureStoreAdmissionController(
        maxBytes: 10,
        maxItems: 2
    )

    let first = try await controller.reserve(bytes: 6)
    do {
        _ = try await controller.reserve(bytes: 5)
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

    try await controller.release(first)
    let snapshot = await controller.snapshot()
    #expect(snapshot.reservedBytes == 0)
    #expect(snapshot.reservedItems == 0)
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
