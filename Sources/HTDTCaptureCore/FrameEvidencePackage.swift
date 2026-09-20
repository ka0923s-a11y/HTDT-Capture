import Foundation

public enum FrameEvidencePackageError: Error, Sendable, Equatable {
    case invalidPixelReference
    case invalidDepthReference
    case invalidConfidenceReference
    case unexpectedDepthPayload
    case unexpectedConfidencePayload
}

public struct FrameEvidencePackage: Sendable, Equatable {
    public let descriptor: FrameEvidenceDescriptor
    public let descriptorPath: String
    public let descriptorData: Data
    public let pixelPayload: Data
    public let depthPayload: Data?
    public let confidencePayload: Data?

    init(
        descriptor: FrameEvidenceDescriptor,
        descriptorPath: String,
        descriptorData: Data,
        pixelPayload: Data,
        depthPayload: Data?,
        confidencePayload: Data?
    ) {
        self.descriptor = descriptor
        self.descriptorPath = descriptorPath
        self.descriptorData = descriptorData
        self.pixelPayload = pixelPayload
        self.depthPayload = depthPayload
        self.confidencePayload = confidencePayload
    }

    public var capturedDepthCount: Int {
        depthPayload == nil ? 0 : 1
    }

    public var payloadDeclarations: [BundlePayloadDeclaration] {
        var declarations: [BundlePayloadDeclaration] = [
            BundlePayloadDeclaration(
                path: descriptor.pixelRelativePath,
                mediaType: "application/vnd.htdt.pixelbin",
                producer: "frame_capture",
                provenanceClass: .arkitFrameObservation,
                role: .canonical
            ),
        ]

        var descriptorSourceRefs = [
            "path:\(descriptor.pixelRelativePath)"
        ]

        if let depth = descriptor.depth {
            declarations.append(
                BundlePayloadDeclaration(
                    path: depth.depthRelativePath,
                    mediaType: "application/vnd.htdt.depthbin",
                    producer: "depth_capture",
                    provenanceClass: .arkitSceneDepthObservation,
                    role: .canonical
                )
            )
            descriptorSourceRefs.append(
                "path:\(depth.depthRelativePath)"
            )

            if let confidencePath = depth.confidenceRelativePath {
                declarations.append(
                    BundlePayloadDeclaration(
                        path: confidencePath,
                        mediaType: "application/vnd.htdt.confidencebin",
                        producer: "depth_capture",
                        provenanceClass: .arkitSceneDepthObservation,
                        role: .canonical
                    )
                )
                descriptorSourceRefs.append(
                    "path:\(confidencePath)"
                )
            }
        }

        declarations.append(
            BundlePayloadDeclaration(
                path: descriptorPath,
                mediaType: "application/json",
                producer: "frame_capture",
                provenanceClass: .arkitFrameObservation,
                role: .canonical,
                sourceRefs: descriptorSourceRefs.sorted()
            )
        )

        return declarations.sorted {
            BundleLogicalPath.utf8Less($0.path, $1.path)
        }
    }

    public func persist(
        using writer: AtomicCaptureFileWriter
    ) async throws {
        try await writer.write(
            pixelPayload,
            to: CaptureStorePath(descriptor.pixelRelativePath)
        )

        if let depth = descriptor.depth,
           let depthPayload
        {
            try await writer.write(
                depthPayload,
                to: CaptureStorePath(depth.depthRelativePath)
            )
        }

        if let confidencePath =
            descriptor.depth?.confidenceRelativePath,
           let confidencePayload
        {
            try await writer.write(
                confidencePayload,
                to: CaptureStorePath(confidencePath)
            )
        }

        try await writer.write(
            descriptorData,
            to: CaptureStorePath(descriptorPath)
        )
    }
}

public enum FrameEvidencePackageBuilder {
    public static func build(
        descriptor: FrameEvidenceDescriptor,
        pixelPayload: Data,
        depthPayload: Data?,
        confidencePayload: Data?
    ) throws -> FrameEvidencePackage {
        let frameID = descriptor.frameID.description
        let expectedDescriptorPath =
            "evidence/frames/\(frameID).json"
        let expectedPixelPath =
            "evidence/frames/\(frameID).pixelbin"

        guard
            descriptor.pixelRelativePath == expectedPixelPath,
            descriptor.pixelByteCount == pixelPayload.count,
            descriptor.pixelSHA256
                == EvidenceIntegrity.sha256(of: pixelPayload)
        else {
            throw FrameEvidencePackageError.invalidPixelReference
        }

        switch descriptor.depth {
        case nil:
            guard depthPayload == nil else {
                throw FrameEvidencePackageError.unexpectedDepthPayload
            }
            guard confidencePayload == nil else {
                throw FrameEvidencePackageError
                    .unexpectedConfidencePayload
            }

        case let .some(depth):
            let expectedDepthPath =
                "evidence/depth/\(frameID).depthbin"
            guard
                depth.depthRelativePath == expectedDepthPath,
                let depthPayload,
                depth.depthByteCount == depthPayload.count,
                depth.depthSHA256
                    == EvidenceIntegrity.sha256(of: depthPayload)
            else {
                throw FrameEvidencePackageError.invalidDepthReference
            }

            switch (
                depth.confidenceRelativePath,
                depth.confidenceByteCount,
                depth.confidenceSHA256,
                confidencePayload
            ) {
            case (nil, nil, nil, nil):
                break

            case let (
                .some(path),
                .some(byteCount),
                .some(sha256),
                .some(payload)
            ):
                let expectedConfidencePath =
                    "evidence/depth/\(frameID).confidencebin"
                guard
                    path == expectedConfidencePath,
                    byteCount == payload.count,
                    sha256 == EvidenceIntegrity.sha256(of: payload)
                else {
                    throw FrameEvidencePackageError
                        .invalidConfidenceReference
                }

            default:
                throw FrameEvidencePackageError
                    .invalidConfidenceReference
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let descriptorData = try encoder.encode(descriptor)

        return FrameEvidencePackage(
            descriptor: descriptor,
            descriptorPath: expectedDescriptorPath,
            descriptorData: descriptorData,
            pixelPayload: pixelPayload,
            depthPayload: depthPayload,
            confidencePayload: confidencePayload
        )
    }
}
