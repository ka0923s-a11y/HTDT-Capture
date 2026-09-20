import Foundation
import XCTest
@testable import HTDTCaptureCore

final class FrameEvidencePackageTests: XCTestCase {
    func testBuildsFramePackageWithoutInventingDepth() throws {
        let pixel = Data([1, 2, 3, 4])
        let frameID = EvidenceFrameID(
            rawValue: UUID(
                uuidString: "10000000-0000-4000-8000-000000000006"
            )!
        )
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: CaptureSessionID(
                rawValue: UUID(
                    uuidString:
                        "10000000-0000-4000-8000-000000000003"
                )!
            ),
            coordinateSpaceID: CoordinateSpaceID(
                rawValue: UUID(
                    uuidString:
                        "10000000-0000-4000-8000-000000000004"
                )!
            ),
            sessionTimestampSeconds: 12.5,
            worldFromCamera: .identity,
            intrinsics: try CameraIntrinsics3x3(
                values: [
                    1, 0, 0,
                    0, 1, 0,
                    0, 0, 1,
                ]
            ),
            imageWidth: 1,
            imageHeight: 1,
            pixelFormatFourCC: 0,
            pixelRelativePath:
                "evidence/frames/\(frameID).pixelbin",
            pixelByteCount: pixel.count,
            pixelSHA256: EvidenceIntegrity.sha256(of: pixel),
            depthStatus: .unavailable,
            depth: nil
        )

        let package = try FrameEvidencePackageBuilder.build(
            descriptor: descriptor,
            pixelPayload: pixel,
            depthPayload: nil,
            confidencePayload: nil
        )

        XCTAssertEqual(
            package.descriptorPath,
            "evidence/frames/\(frameID).json"
        )
        XCTAssertEqual(package.capturedDepthCount, 0)
        XCTAssertEqual(
            package.payloadDeclarations.map(\.path),
            [
                "evidence/frames/\(frameID).json",
                "evidence/frames/\(frameID).pixelbin",
            ]
        )

        let reopened = try JSONDecoder().decode(
            FrameEvidenceDescriptor.self,
            from: package.descriptorData
        )
        XCTAssertEqual(reopened, descriptor)
    }

    func testBuildsDepthAndConfidenceLineageForExactFrame() throws {
        let pixel = Data([1, 2, 3, 4])
        let depth = Data([5, 6, 7, 8])
        let confidence = Data([9, 10])
        let frameID = EvidenceFrameID(
            rawValue: UUID(
                uuidString: "10000000-0000-4000-8000-000000000006"
            )!
        )
        let depthReference = try DepthEvidenceReference(
            kind: .discreteSceneDepth,
            depthRelativePath:
                "evidence/depth/\(frameID).depthbin",
            depthByteCount: depth.count,
            depthSHA256: EvidenceIntegrity.sha256(of: depth),
            confidenceRelativePath:
                "evidence/depth/\(frameID).confidencebin",
            confidenceByteCount: confidence.count,
            confidenceSHA256:
                EvidenceIntegrity.sha256(of: confidence)
        )
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            sessionTimestampSeconds: 1,
            worldFromCamera: .identity,
            intrinsics: try CameraIntrinsics3x3(
                values: [
                    1, 0, 0,
                    0, 1, 0,
                    0, 0, 1,
                ]
            ),
            imageWidth: 1,
            imageHeight: 1,
            pixelFormatFourCC: 0,
            pixelRelativePath:
                "evidence/frames/\(frameID).pixelbin",
            pixelByteCount: pixel.count,
            pixelSHA256: EvidenceIntegrity.sha256(of: pixel),
            depthStatus: .capturedDiscrete,
            depth: depthReference
        )

        let package = try FrameEvidencePackageBuilder.build(
            descriptor: descriptor,
            pixelPayload: pixel,
            depthPayload: depth,
            confidencePayload: confidence
        )

        XCTAssertEqual(package.capturedDepthCount, 1)
        let byPath = Dictionary(
            uniqueKeysWithValues:
                package.payloadDeclarations.map {
                    ($0.path, $0)
                }
        )
        XCTAssertEqual(
            byPath[package.descriptorPath]?.sourceRefs,
            [
                "path:evidence/depth/\(frameID).confidencebin",
                "path:evidence/depth/\(frameID).depthbin",
                "path:evidence/frames/\(frameID).pixelbin",
            ]
        )
        XCTAssertEqual(
            byPath[
                "evidence/depth/\(frameID).depthbin"
            ]?.provenanceClass,
            .arkitSceneDepthObservation
        )
    }

    func testRejectsPayloadWhoseHashDoesNotMatchDescriptor() throws {
        let frameID = EvidenceFrameID()
        let expected = Data([1, 2, 3])
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            sessionTimestampSeconds: 1,
            worldFromCamera: .identity,
            intrinsics: try CameraIntrinsics3x3(
                values: [
                    1, 0, 0,
                    0, 1, 0,
                    0, 0, 1,
                ]
            ),
            imageWidth: 1,
            imageHeight: 1,
            pixelFormatFourCC: 0,
            pixelRelativePath:
                "evidence/frames/\(frameID).pixelbin",
            pixelByteCount: expected.count,
            pixelSHA256: EvidenceIntegrity.sha256(of: expected)
        )

        XCTAssertThrowsError(
            try FrameEvidencePackageBuilder.build(
                descriptor: descriptor,
                pixelPayload: Data([9, 9, 9]),
                depthPayload: nil,
                confidencePayload: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? FrameEvidencePackageError,
                .invalidPixelReference
            )
        }
    }
}


extension FrameEvidencePackageTests {
    func testDerivedHEICPreviewIsNonCanonicalAndEvidenceLinked()
        throws
    {
        let pixel = Data([1, 2, 3, 4])
        let preview = Data([0x00, 0x00, 0x00, 0x18])
        let frameID = EvidenceFrameID()
        let descriptor = try FrameEvidenceDescriptor(
            frameID: frameID,
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            sessionTimestampSeconds: 1,
            worldFromCamera: .identity,
            intrinsics: try CameraIntrinsics3x3(
                values: [
                    1, 0, 0,
                    0, 1, 0,
                    0, 0, 1,
                ]
            ),
            imageWidth: 1,
            imageHeight: 1,
            pixelFormatFourCC: 0,
            pixelRelativePath:
                "evidence/frames/\(frameID).pixelbin",
            pixelByteCount: pixel.count,
            pixelSHA256: EvidenceIntegrity.sha256(of: pixel)
        )

        let package = try FrameEvidencePackageBuilder.build(
            descriptor: descriptor,
            pixelPayload: pixel,
            depthPayload: nil,
            confidencePayload: nil,
            previewPayload: preview
        )
        let previewRef = try XCTUnwrap(package.preview)
        XCTAssertEqual(
            previewRef.path,
            "evidence/frames/\(frameID).preview.heic"
        )
        XCTAssertEqual(previewRef.byteCount, preview.count)
        XCTAssertEqual(
            previewRef.sha256,
            EvidenceIntegrity.sha256(of: preview)
        )

        let declaration = try XCTUnwrap(
            package.payloadDeclarations.first {
                $0.path == previewRef.path
            }
        )
        XCTAssertEqual(declaration.role, .derived)
        XCTAssertEqual(
            declaration.provenanceClass,
            .captureAppDerived
        )
        XCTAssertEqual(
            declaration.sourceRefs,
            ["path:\(package.descriptorPath)"]
        )
    }
}
