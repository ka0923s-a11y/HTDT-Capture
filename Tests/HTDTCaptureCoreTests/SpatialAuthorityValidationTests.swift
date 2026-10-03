import Foundation
import Testing
@testable import HTDTCaptureCore

// legacy bolph71656-ai/HTDT-Capture#158: spatial transform and camera intrinsics authorities must reject
// structurally valid but nonphysical matrices.

@Test
func identityAndTranslatedPosesAreValid() throws {
    _ = try Matrix4x4F(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ])
    let translated = try Matrix4x4F(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        -3.25, 0.5, 12.75, 1,
    ])
    #expect(translated.values[12] == -3.25)
}

@Test
func rotatedPoseIsValid() throws {
    // 90-degree yaw: column-major rigid transform.
    let yaw = try Matrix4x4F(values: [
        0, 0, -1, 0,
        0, 1, 0, 0,
        1, 0, 0, 0,
        2, 0.5, -1, 1,
    ])
    #expect(yaw.values[0] == 0)
}

@Test
func nonFiniteElementsAreRejected() {
    var values = Matrix4x4F.identity.values
    values[0] = .nan
    #expect(throws: Matrix4x4FError.nonFinite) {
        _ = try Matrix4x4F(values: values)
    }
    values[0] = .infinity
    #expect(throws: Matrix4x4FError.nonFinite) {
        _ = try Matrix4x4F(values: values)
    }
}

@Test
func wrongElementCountIsRejected() {
    #expect(throws: Matrix4x4FError.invalidElementCount(15)) {
        _ = try Matrix4x4F(values: Array(repeating: 0, count: 15))
    }
}

@Test
func zeroMatrixIsRejected() {
    #expect(throws: Matrix4x4FError.self) {
        _ = try Matrix4x4F(values: Array(repeating: 0, count: 16))
    }
}

@Test
func perspectiveRowIsRejected() {
    #expect(throws: Matrix4x4FError.nonHomogeneousTransform) {
        _ = try Matrix4x4F(values: [
            1, 0, 0, 0.5,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ])
    }
    #expect(throws: Matrix4x4FError.nonHomogeneousTransform) {
        _ = try Matrix4x4F(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 2,
        ])
    }
}

@Test
func scaledBasisIsRejected() {
    // Column 0 scaled by 2.
    #expect(throws: Matrix4x4FError.nonOrthonormalBasis) {
        _ = try Matrix4x4F(values: [
            2, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ])
    }
}

@Test
func shearedBasisIsRejected() {
    // Column 0 bent toward y (not orthogonal to column 1).
    let sheared: [Float] = [
        0.9, 0.5, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ]
    #expect(throws: Matrix4x4FError.nonOrthonormalBasis) {
        _ = try Matrix4x4F(values: sheared)
    }
}

@Test
func mirroredBasisIsRejected() {
    // Reflection: det = -1.
    #expect(throws: Matrix4x4FError.invalidDeterminant) {
        _ = try Matrix4x4F(values: [
            -1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ])
    }
}

@Test
func rigidTransformSurvivesRoundTripThroughDecoder() throws {
    let pose = try Matrix4x4F(values: [
        0, 0, -1, 0,
        0, 1, 0, 0,
        1, 0, 0, 0,
        2, 0.5, -1, 1,
    ])
    let data = try JSONEncoder().encode(pose)
    #expect(try JSONDecoder().decode(Matrix4x4F.self, from: data) == pose)
}

@Test
func invalidPoseFailsDecoding() throws {
    let json = """
        {"representation":"column_major_4x4_f32","values":[\
        2,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}
        """
    #expect(throws: Matrix4x4FError.nonOrthonormalBasis) {
        _ = try JSONDecoder().decode(
            Matrix4x4F.self,
            from: Data(json.utf8)
        )
    }
}

@Test
func validPinholeIntrinsicsAreAccepted() throws {
    let intrinsics = try CameraIntrinsics3x3(values: [
        1450.5, 0, 0,
        0, 1450.5, 0,
        960.0, 720.0, 1,
    ])
    #expect(intrinsics.fx == 1450.5)
    #expect(intrinsics.fy == 1450.5)
    #expect(intrinsics.cx == 960.0)
    #expect(intrinsics.cy == 720.0)
}

@Test
func identityIntrinsicsAreAccepted() throws {
    _ = try CameraIntrinsics3x3(values: [
        1, 0, 0,
        0, 1, 0,
        0, 0, 1,
    ])
}

@Test
func nonPositiveFocalLengthIsRejected() {
    #expect(throws: CameraIntrinsicsError.nonPositiveFocalLength) {
        _ = try CameraIntrinsics3x3(values: [
            0, 0, 0,
            0, 1450, 0,
            960, 720, 1,
        ])
    }
    #expect(throws: CameraIntrinsicsError.nonPositiveFocalLength) {
        _ = try CameraIntrinsics3x3(values: [
            1450, 0, 0,
            0, -3, 0,
            960, 720, 1,
        ])
    }
}

@Test
func nonPinholeStructureIsRejected() {
    // Non-zero skew / projective terms.
    #expect(throws: CameraIntrinsicsError.nonPinholeStructure) {
        _ = try CameraIntrinsics3x3(values: [
            1450, 0.5, 0,
            0, 1450, 0,
            960, 720, 1,
        ])
    }
    // Bottom-right not equal to one.
    #expect(throws: CameraIntrinsicsError.nonPinholeStructure) {
        _ = try CameraIntrinsics3x3(values: [
            1450, 0, 0,
            0, 1450, 0,
            960, 720, 2,
        ])
    }
}

@Test
func negativePrincipalPointIsRejected() {
    #expect(throws: CameraIntrinsicsError.invalidPrincipalPoint) {
        _ = try CameraIntrinsics3x3(values: [
            1450, 0, 0,
            0, 1450, 0,
            -10, 720, 1,
        ])
    }
}

@Test
func principalPointBeyondImageBoundsIsRejected() throws {
    let hash = try EvidenceSHA256(
        String(repeating: "ab", count: 32)
    )
    let intrinsics = try CameraIntrinsics3x3(values: [
        1450, 0, 0,
        0, 1450, 0,
        2000, 720, 1,
    ])
    #expect(
        throws: FrameEvidenceDescriptorError.principalPointOutsideImage
    ) {
        _ = try FrameEvidenceDescriptor(
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            sessionTimestampSeconds: 1.0,
            worldFromCamera: .identity,
            intrinsics: intrinsics,
            imageWidth: 1920,
            imageHeight: 1440,
            pixelFormatFourCC: 0x34323066,
            pixelRelativePath: "evidence/frames/x.pixelbin",
            pixelByteCount: 32,
            pixelSHA256: hash
        )
    }
}
