import Foundation
@testable import HTDTCaptureCore

enum BundleValidationFixture {
    static let sessionUUID = "00000000-0000-4000-8000-000000000003"
    static let spaceUUID = "00000000-0000-4000-8000-000000000004"
    static let frameUUID = "00000000-0000-4000-8000-000000000010"
    static let anchorUUID = "00000000-0000-4000-8000-000000000011"

    static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func write(
        _ data: Data,
        to path: String,
        in root: URL
    ) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    static func canonical(_ value: StrictJSONValue) throws -> Data {
        try CanonicalJSONProfile.canonicalBytes(of: value)
    }

    static func entry(
        path: String,
        data: Data,
        mediaType: String
    ) throws -> BundleFileEntry {
        // Reserved canonical paths must carry the bound
        // producer/provenance metadata or the manifest rejects them
        // before any payload check runs (issue #151).
        let binding = BundleReservedPaths.binding(for: path)
        return try BundleFileEntry(
            path: path,
            bytes: data.count,
            mediaType: mediaType,
            sha256: EvidenceIntegrity.sha256(of: data),
            producer: binding?.producer ?? "test",
            provenanceClass: binding?.provenanceClass ?? .captureAppDerived,
            role: binding?.role ?? .canonical
        )
    }

    static func manifest(
        entries: [BundleFileEntry]
    ) throws -> BundleManifest {
        try BundleManifest(
            captureSeriesID: CaptureSeriesID(),
            captureRevisionID: CaptureRevisionID(),
            parentRevisionID: nil,
            captureSessionIDs: [CaptureSessionID()],
            coordinateSpaceIDs: [CoordinateSpaceID()],
            createdAtUTC: "2026-09-20T00:00:00Z",
            finalizedAtUTC: "2026-09-20T00:01:00Z",
            app: BundleAppIdentity(version: "0.1.0", build: "test"),
            files: entries
        )
    }

    static func stage(
        _ root: URL,
        payloads: [(path: String, data: Data, mediaType: String)]
    ) throws {
        var entries: [BundleFileEntry] = []
        for payload in payloads {
            try write(payload.data, to: payload.path, in: root)
            entries.append(
                try entry(
                    path: payload.path,
                    data: payload.data,
                    mediaType: payload.mediaType
                )
            )
        }
        let manifest = try manifest(entries: entries)
        try manifest.canonicalBytes().write(
            to: root.appendingPathComponent("manifest.json")
        )
    }

    static func sessionValue() -> StrictJSONValue {
        .object([
            ("schema", .string("htdt.capture.session")),
            ("schema_version", .string("1.0.0")),
            ("capture_session_id", .string(sessionUUID)),
            ("coordinate_space_id", .string(spaceUUID)),
            ("capture_mode", .string("roomplan_mesh")),
            ("started_at", .string("2026-09-20T00:00:00Z")),
            ("configuration_ref", .string("session/capture-configuration.json")),
            ("timing_ref", .string("session/timing.json")),
        ])
    }

    static func qualityValue() -> StrictJSONValue {
        let completeness = StrictJSONValue.object([
            ("required", .array([])),
            ("present", .array([])),
            ("missing", .array([])),
        ])
        return .object([
            ("schema", .string("htdt.capture.quality")),
            ("schema_version", .string("1.0.0")),
            ("ruleset_version", .string("1.0.0")),
            ("ready_for_htdt_ingestion", .boolean(true)),
            ("tracking_events", .array([])),
            ("roomplan_status", .string("completed")),
            ("active_mesh_anchor_count", .integer("2")),
            ("evidence_frame_count", .integer("1")),
            ("depth_evidence_count", .integer("1")),
            ("annotation_completeness", completeness),
            ("measurement_completeness", completeness),
            ("resource_events", .array([])),
            ("integrity_status", .string("pass")),
            ("benchmark_refs", .array([])),
            ("diagnostics", .array([])),
        ])
    }

    static func entitiesValue() -> StrictJSONValue {
        .object([
            ("schema", .string("htdt.capture.entities")),
            ("schema_version", .string("1.0.0")),
            ("entities", .array([])),
        ])
    }

    static func matrix4Value() -> StrictJSONValue {
        .object([
            ("representation", .string("column_major_4x4_f32")),
            (
                "values",
                .array(
                    (0 ..< 16).map { .number($0 == 0 || $0 % 5 == 0 ? 1 : 0) }
                )
            ),
        ])
    }

    static func matrix3Value() -> StrictJSONValue {
        .object([
            ("representation", .string("column_major_3x3_f32")),
            ("values", .array((0 ..< 9).map { _ in .number(1) })),
        ])
    }

    static func meshAnchorsValue(
        geometryPath: String,
        geometrySHA256: String,
        vertexCount: Int,
        faceCount: Int
    ) -> StrictJSONValue {
        .object([
            ("schema", .string("htdt.capture.mesh-anchors")),
            ("schema_version", .string("1.0.0")),
            (
                "anchors",
                .array([
                    .object([
                        ("anchor_id", .string(anchorUUID)),
                        ("capture_session_id", .string(sessionUUID)),
                        ("coordinate_space_id", .string(spaceUUID)),
                        (
                            "T_world_from_mesh_anchor",
                            matrix4Value()
                        ),
                        ("session_timestamp_s", .number(1)),
                        ("vertex_count", .integer("\(vertexCount)")),
                        ("face_count", .integer("\(faceCount)")),
                        ("geometry_path", .string(geometryPath)),
                        (
                            "geometry_sha256",
                            .string(geometrySHA256)
                        ),
                    ]),
                ])
            ),
        ])
    }

    static func frameDescriptorValue(
        pixelPath: String,
        pixelByteCount: Int,
        pixelSHA256: String,
        imageWidth: Int,
        imageHeight: Int,
        pixelFormatFourCC: Int,
        depthStatus: String = "not_requested",
        depth: StrictJSONValue? = nil
    ) -> StrictJSONValue {
        var members: [(key: String, value: StrictJSONValue)] = [
            ("frame_id", .string(frameUUID)),
            ("capture_session_id", .string(sessionUUID)),
            ("coordinate_space_id", .string(spaceUUID)),
            ("session_timestamp_s", .number(1.5)),
            ("T_world_from_camera", matrix4Value()),
            ("intrinsics", matrix3Value()),
            ("image_width", .integer("\(imageWidth)")),
            ("image_height", .integer("\(imageHeight)")),
            ("pixel_format_fourcc", .integer("\(pixelFormatFourCC)")),
            ("pixel_relative_path", .string(pixelPath)),
            ("pixel_byte_count", .integer("\(pixelByteCount)")),
            ("pixel_sha256", .string(pixelSHA256)),
            ("exif_allowlisted", .object([])),
            ("depth_status", .string(depthStatus)),
        ]
        if let depth {
            members.append(("depth", depth))
        }
        return .object(members)
    }

    static func depthReferenceValue(
        kind: String = "scene_depth",
        depthPath: String,
        depthByteCount: Int,
        depthSHA256: String,
        confidencePath: String? = nil,
        confidenceByteCount: Int? = nil,
        confidenceSHA256: String? = nil
    ) -> StrictJSONValue {
        var members: [(key: String, value: StrictJSONValue)] = [
            ("kind", .string(kind)),
            ("depth_relative_path", .string(depthPath)),
            ("depth_byte_count", .integer("\(depthByteCount)")),
            ("depth_sha256", .string(depthSHA256)),
        ]
        if let confidencePath, let confidenceByteCount,
           let confidenceSHA256
        {
            members.append(
                ("confidence_relative_path", .string(confidencePath))
            )
            members.append(
                (
                    "confidence_byte_count",
                    .integer("\(confidenceByteCount)")
                )
            )
            members.append(
                ("confidence_sha256", .string(confidenceSHA256))
            )
        }
        return .object(members)
    }

    static func meshPayload(
        vertexCount: Int,
        faceCount: Int
    ) throws -> Data {
        let vertices = (0 ..< vertexCount).map {
            Float3(Float($0), Float($0), 0)
        }
        var indices: [UInt32] = []
        let modulus = UInt32(max(vertexCount, 1))
        for face in 0 ..< faceCount {
            indices.append(UInt32((face * 3) % Int(modulus)))
            indices.append(UInt32((face * 3 + 1) % Int(modulus)))
            indices.append(UInt32((face * 3 + 2) % Int(modulus)))
        }
        let geometry = try MeshGeometryPayload(
            vertices: vertices,
            triangleIndices: indices
        )
        return try MeshBinaryCodec.encode(geometry)
    }

    static func pixelPayload(
        width: Int,
        height: Int,
        fourCC: UInt32 = 0x3432_3066
    ) throws -> Data {
        let bytesPerRow = width * 4
        let plane = try PackedPixelPlane(
            width: width,
            height: height,
            sourceBytesPerRow: bytesPerRow,
            packedBytesPerRow: bytesPerRow,
            bytes: Data(repeating: 0xAB, count: bytesPerRow * height)
        )
        let buffer = try PackedPixelBuffer(
            width: width,
            height: height,
            pixelFormatFourCC: fourCC,
            planes: [plane]
        )
        return try PixelBufferBinaryCodec.encode(buffer)
    }

    static func depthPayload(width: Int, height: Int) throws -> Data {
        let payload = try DepthMapPayload(
            width: width,
            height: height,
            valuesMeters: Array(repeating: 1, count: width * height)
        )
        return try DepthBinaryCodec.encode(payload)
    }

    static func confidencePayload(width: Int, height: Int) throws -> Data {
        let payload = try ConfidenceMapPayload(
            width: width,
            height: height,
            values: Array(repeating: 2, count: width * height)
        )
        return try ConfidenceBinaryCodec.encode(payload)
    }
}
