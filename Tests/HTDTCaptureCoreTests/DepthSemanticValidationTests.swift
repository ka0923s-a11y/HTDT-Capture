import Foundation
import Testing
@testable import HTDTCaptureCore

// MARK: - Canonical depth/confidence semantics (legacy bolph71656-ai/HTDT-Capture#164)
//
// The platform adapter (DepthDataSnapshotAdapter, iOS-only) enforces the
// v1 sample policy at the capture boundary: only finite positive depth
// is a valid observation, invalid samples are normalized to zero with a
// required validity mask, and confidence bytes are limited to the
// ARConfidenceLevel raw domain. These tests pin the model/codec side of
// that contract with mock payloads.

@Test
func invalidDepthSamplesRoundTripAsZeroWithValidityMask() throws {
    // Mirrors the adapter output for zero/negative/non-finite source
    // samples: stored as 0 and marked invalid, never silently valid.
    let payload = try DepthMapPayload(
        width: 2,
        height: 2,
        valuesMeters: [1.5, 0, 0, 2.0],
        validityMask: [1, 0, 0, 1]
    )

    let decoded = try DepthBinaryCodec.decode(
        DepthBinaryCodec.encode(payload)
    )

    #expect(decoded == payload)
    #expect(decoded.validityMask == [1, 0, 0, 1])
    #expect(decoded.valuesMeters[1] == 0)
    #expect(decoded.valuesMeters[2] == 0)
}

@Test
func depthCodecDecodeRejectsNonFiniteStoredValues() throws {
    var payload = try DepthBinaryCodec.encode(
        DepthMapPayload(
            width: 2,
            height: 1,
            valuesMeters: [1.0, 2.0]
        )
    )
    // Header is 32 bytes; overwrite the first float32 lane with NaN.
    payload.replaceSubrange(32..<36, with: [0x00, 0x00, 0xC0, 0x7F])

    #expect(throws: DepthBinaryCodecError.self) {
        _ = try DepthBinaryCodec.decode(payload)
    }
}

@Test
func depthModelRejectsMismatchedDimensionsBeforeUse() {
    #expect(throws: DepthEvidenceError.self) {
        _ = try DepthMapPayload(
            width: 3,
            height: 2,
            valuesMeters: [1, 1, 1]
        )
    }
    #expect(throws: DepthEvidenceError.self) {
        _ = try DepthMapPayload(
            width: 0,
            height: 2,
            valuesMeters: []
        )
    }
}

@Test
func confidencePayloadRoundTripsSupportedConfidenceDomain() throws {
    // ARConfidenceLevel raw domain: low = 0, medium = 1, high = 2.
    let payload = try ConfidenceMapPayload(
        width: 3,
        height: 1,
        values: [0, 1, 2]
    )

    let decoded = try ConfidenceBinaryCodec.decode(
        ConfidenceBinaryCodec.encode(payload)
    )

    #expect(decoded == payload)
    #expect(decoded.values == [0, 1, 2])
}

@Test
func confidenceModelRejectsMismatchedDimensionsBeforeUse() {
    #expect(throws: DepthEvidenceError.self) {
        _ = try ConfidenceMapPayload(
            width: 2,
            height: 2,
            values: [0, 1, 2]
        )
    }
}
