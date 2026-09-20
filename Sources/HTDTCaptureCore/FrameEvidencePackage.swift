import Foundation

public struct DerivedFramePreviewReference:
    Sendable,
    Equatable
{
    public let path: String
    public let byteCount: Int
    public let sha256: EvidenceSHA256

    public init(
        path: String,
        byteCount: Int,
        sha256: EvidenceSHA256
    ) {
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

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
    public let previewPayload: Data?
    public let preview: DerivedFramePreviewReference?

    init(
        descriptor: FrameEvidenceDescriptor,
        descriptorPath: String,
        descriptorData: Data,
        pixelPayload: Data,
        depthPayload: Data?,
        confidencePayload: Data?,
        previewPayload: Data?,
        preview: DerivedFramePreviewReference?
    ) {
        self.descriptor = descriptor
        self.descriptorPath = descriptorPath
        self.descriptorData = descriptorData
        self.pixelPayload = pixelPayload
        self.depthPayload = depthPayload
        self.confidencePayload = confidencePayload
        self.previewPayload = previewPayload
        self.preview = preview
    }

    public var capturedDepthCount: Int {
        depthPayload == nil ? 0 : 1
    }

    public var canonicalPayloadDeclarations: [BundlePayloadDeclaration] {
        payloadDeclarations.filter { $0.role == .canonical }
    }

    public var previewPayloadDeclaration: BundlePayloadDeclaration? {
        payloadDeclarations.first { $0.role == .derived }
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

        if let preview {
            declarations.append(
                BundlePayloadDeclaration(
                    path: preview.path,
                    mediaType: "image/heic",
                    producer: "frame_preview",
                    provenanceClass: .captureAppDerived,
                    role: .derived,
                    sourceRefs: ["path:\(descriptorPath)"]
                )
            )
        }

        return declarations.sorted {
            BundleLogicalPath.utf8Less($0.path, $1.path)
        }
    }

    public func persistCanonical(
        using writer: AtomicCaptureFileWriter
    ) async throws {
        // Persist the canonical frame as one writer-actor transaction. A
        // filesystem failure must not leave a newly-created subset behind,
        // while byte-identical files from an earlier interrupted attempt may
        // be reused safely.
        var requests: [CaptureFileWriteRequest] = [
            try CaptureFileWriteRequest(
                data: pixelPayload,
                path: CaptureStorePath(
                    descriptor.pixelRelativePath
                )
            ),
        ]

        if let depth = descriptor.depth,
           let depthPayload
        {
            requests.append(
                try CaptureFileWriteRequest(
                    data: depthPayload,
                    path: CaptureStorePath(
                        depth.depthRelativePath
                    )
                )
            )
        }

        if let confidencePath =
            descriptor.depth?.confidenceRelativePath,
           let confidencePayload
        {
            requests.append(
                try CaptureFileWriteRequest(
                    data: confidencePayload,
                    path: CaptureStorePath(confidencePath)
                )
            )
        }

        requests.append(
            try CaptureFileWriteRequest(
                data: descriptorData,
                path: CaptureStorePath(descriptorPath)
            )
        )

        try await writer.writeBatchIfIdentical(requests)
    }

    public func persistPreview(
        using writer: AtomicCaptureFileWriter
    ) async throws {
        guard let preview,
              let previewPayload
        else {
            return
        }

        try await writer.writeIfIdentical(
            previewPayload,
            to: CaptureStorePath(preview.path)
        )
    }

    public func persist(
        using writer: AtomicCaptureFileWriter
    ) async throws {
        try await persistCanonical(using: writer)
        try await persistPreview(using: writer)
    }
}

public enum FrameEvidencePackageBuilder {
    public static func build(
        descriptor: FrameEvidenceDescriptor,
        pixelPayload: Data,
        depthPayload: Data?,
        confidencePayload: Data?,
        previewPayload: Data? = nil
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

        let preview: DerivedFramePreviewReference?
        if let previewPayload {
            preview = DerivedFramePreviewReference(
                path:
                    "evidence/frames/\(frameID).preview.heic",
                byteCount: previewPayload.count,
                sha256:
                    EvidenceIntegrity.sha256(
                        of: previewPayload
                    )
            )
        } else {
            preview = nil
        }

        return FrameEvidencePackage(
            descriptor: descriptor,
            descriptorPath: expectedDescriptorPath,
            descriptorData: descriptorData,
            pixelPayload: pixelPayload,
            depthPayload: depthPayload,
            confidencePayload: confidencePayload,
            previewPayload: previewPayload,
            preview: preview
        )
    }
}
