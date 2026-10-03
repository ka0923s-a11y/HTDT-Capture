import HTDTCaptureCore

#if os(iOS) && canImport(ARKit) && canImport(Metal)
import ARKit
import Metal
import simd

public enum ARMeshSnapshotAdapterError: Error {
    case unsupportedVertexFormat
    case unsupportedNormalFormat
    case unsupportedIndexWidth(Int)
    case nonTriangleGeometry(Int)
    case invalidGeometry
}

public enum ARMeshSnapshotAdapter {
    public static func snapshot(
        anchor: ARMeshAnchor,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        sessionTimestampSeconds: Double?
    ) throws -> MeshAnchorSnapshot {
        let geometry = anchor.geometry

        guard geometry.vertices.format == .float3,
              geometry.vertices.componentsPerVector >= 3,
              sourceHasReadableRange(
                geometry.vertices,
                bytesPerVector: MemoryLayout<Float>.size * 3
              )
        else {
            throw ARMeshSnapshotAdapterError.unsupportedVertexFormat
        }

        guard geometry.normals.format == .float3,
              geometry.normals.componentsPerVector >= 3,
              sourceHasReadableRange(
                geometry.normals,
                bytesPerVector: MemoryLayout<Float>.size * 3
              )
        else {
            throw ARMeshSnapshotAdapterError.unsupportedNormalFormat
        }

        var vertices: [Float3] = []
        vertices.reserveCapacity(geometry.vertices.count)
        for index in 0..<geometry.vertices.count {
            vertices.append(readFloat3(source: geometry.vertices, index: index))
        }

        var normals: [Float3] = []
        normals.reserveCapacity(geometry.normals.count)
        for index in 0..<geometry.normals.count {
            normals.append(readFloat3(source: geometry.normals, index: index))
        }

        let faces = geometry.faces
        guard faces.indexCountPerPrimitive == 3 else {
            throw ARMeshSnapshotAdapterError.nonTriangleGeometry(
                faces.indexCountPerPrimitive
            )
        }
        guard faces.bytesPerIndex == 2 || faces.bytesPerIndex == 4 else {
            throw ARMeshSnapshotAdapterError.unsupportedIndexWidth(
                faces.bytesPerIndex
            )
        }
        guard elementHasReadableRange(faces) else {
            throw ARMeshSnapshotAdapterError.invalidGeometry
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(faces.count * faces.indexCountPerPrimitive)
        let faceBase = faces.buffer.contents()

        for primitive in 0..<faces.count {
            for localIndex in 0..<faces.indexCountPerPrimitive {
                let flatIndex = primitive * faces.indexCountPerPrimitive + localIndex
                let byteOffset = flatIndex * faces.bytesPerIndex
                let pointer = faceBase.advanced(by: byteOffset)

                switch faces.bytesPerIndex {
                case 2:
                    indices.append(UInt32(readUInt16LE(pointer)))
                case 4:
                    indices.append(readUInt32LE(pointer))
                default:
                    throw ARMeshSnapshotAdapterError
                        .unsupportedIndexWidth(faces.bytesPerIndex)
                }
            }
        }

        var classifications: [UInt8]?
        if let source = geometry.classification {
            guard source.format == .uchar,
                  source.componentsPerVector >= 1,
                  sourceHasReadableRange(
                    source,
                    bytesPerVector: MemoryLayout<UInt8>.size
                  ),
                  source.count >= faces.count
            else {
                throw ARMeshSnapshotAdapterError.invalidGeometry
            }

            var values: [UInt8] = []
            values.reserveCapacity(faces.count)
            for index in 0..<faces.count {
                let pointer = source.buffer.contents().advanced(
                    by: source.offset + index * source.stride
                )
                values.append(
                    pointer.assumingMemoryBound(to: UInt8.self).pointee
                )
            }
            classifications = values
        }

        let payload: MeshGeometryPayload
        do {
            payload = try MeshGeometryPayload(
                vertices: vertices,
                normals: normals,
                triangleIndices: indices,
                faceClassifications: classifications
            )
        } catch {
            throw ARMeshSnapshotAdapterError.invalidGeometry
        }

        return MeshAnchorSnapshot(
            anchorID: anchor.identifier,
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            worldFromAnchor: try matrix(anchor.transform),
            sessionTimestampSeconds: sessionTimestampSeconds,
            geometry: payload
        )
    }

    private static func sourceHasReadableRange(
        _ source: ARGeometrySource,
        bytesPerVector: Int
    ) -> Bool {
        guard source.count >= 0,
              source.offset >= 0,
              source.stride >= bytesPerVector,
              bytesPerVector > 0
        else {
            return false
        }

        guard source.count > 0 else {
            return source.offset <= source.buffer.length
        }

        let (strideBytes, strideOverflow) =
            (source.count - 1)
                .multipliedReportingOverflow(by: source.stride)
        guard !strideOverflow else {
            return false
        }
        let (lastStart, offsetOverflow) =
            source.offset.addingReportingOverflow(strideBytes)
        guard !offsetOverflow else {
            return false
        }
        let (requiredBytes, sizeOverflow) =
            lastStart.addingReportingOverflow(bytesPerVector)
        return !sizeOverflow
            && requiredBytes <= source.buffer.length
    }

    private static func elementHasReadableRange(
        _ element: ARGeometryElement
    ) -> Bool {
        guard element.count >= 0,
              element.indexCountPerPrimitive > 0,
              element.bytesPerIndex > 0
        else {
            return false
        }

        let (indexCount, countOverflow) =
            element.count.multipliedReportingOverflow(
                by: element.indexCountPerPrimitive
            )
        guard !countOverflow else {
            return false
        }
        let (requiredBytes, byteOverflow) =
            indexCount.multipliedReportingOverflow(
                by: element.bytesPerIndex
            )
        return !byteOverflow
            && requiredBytes <= element.buffer.length
    }

    private static func readFloat3(
        source: ARGeometrySource,
        index: Int
    ) -> Float3 {
        let pointer = source.buffer.contents().advanced(
            by: source.offset + index * source.stride
        )
        let values = pointer.assumingMemoryBound(to: Float.self)
        return Float3(values[0], values[1], values[2])
    }

    private static func readUInt16LE(
        _ pointer: UnsafeMutableRawPointer
    ) -> UInt16 {
        let bytes = pointer.assumingMemoryBound(to: UInt8.self)
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    private static func readUInt32LE(
        _ pointer: UnsafeMutableRawPointer
    ) -> UInt32 {
        let bytes = pointer.assumingMemoryBound(to: UInt8.self)
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }

    private static func matrix(
        _ value: simd_float4x4
    ) throws -> Matrix4x4F {
        try Matrix4x4F(values: [
            value.columns.0.x, value.columns.0.y, value.columns.0.z, value.columns.0.w,
            value.columns.1.x, value.columns.1.y, value.columns.1.z, value.columns.1.w,
            value.columns.2.x, value.columns.2.y, value.columns.2.z, value.columns.2.w,
            value.columns.3.x, value.columns.3.y, value.columns.3.z, value.columns.3.w,
        ])
    }
}
#endif
