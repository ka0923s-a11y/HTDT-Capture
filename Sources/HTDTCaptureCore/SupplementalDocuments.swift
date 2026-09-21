import Foundation

public enum SupplementalDocumentError: Error, Sendable, Equatable {
    case emptyPayload
    case declarationPathMismatch
    case reservedPathMetadataMismatch(String)
    case unboundProvenanceClass(String)
    case duplicateCoordinateSpace
    case duplicateCaptureSession
}

/// A working-set payload committed through the store's generic
/// supplemental-document path (issues #222/#226/#227/#240/#249/#293).
/// Feature modules own their wire documents; this type carries the
/// final bytes plus the manifest declaration and lets the store
/// enforce write-once, admission, coordinate-authority, and
/// declaration rules exactly like the typed families.
public struct WorkingSetSupplementalDocument: Sendable, Equatable {
    public let path: String
    public let data: Data
    public let declaration: BundlePayloadDeclaration
    /// Coordinate spaces the payload references — each must equal the
    /// revision's bound space.
    public let coordinateSpaceIDs: [CoordinateSpaceID]
    /// Capture sessions the payload claims; each must equal the bound
    /// session once one is bound.
    public let captureSessionIDs: [CaptureSessionID]

    public init(
        path: String,
        data: Data,
        declaration: BundlePayloadDeclaration,
        coordinateSpaceIDs: [CoordinateSpaceID] = [],
        captureSessionIDs: [CaptureSessionID] = []
    ) throws {
        try BundleLogicalPath.validate(path)
        guard !data.isEmpty else {
            throw SupplementalDocumentError.emptyPayload
        }
        guard declaration.path == path else {
            throw SupplementalDocumentError.declarationPathMismatch
        }
        if let binding = BundleReservedPaths.binding(for: path) {
            guard declaration.mediaType == binding.mediaType,
                  declaration.producer == binding.producer,
                  declaration.provenanceClass
                    == binding.provenanceClass,
                  declaration.role == binding.role
            else {
                throw SupplementalDocumentError
                    .reservedPathMetadataMismatch(path)
            }
        } else {
            guard BundleReservedPaths.unrestrictedProvenanceClasses
                .contains(declaration.provenanceClass)
            else {
                throw SupplementalDocumentError
                    .unboundProvenanceClass(path)
            }
        }
        guard Set(coordinateSpaceIDs).count
                == coordinateSpaceIDs.count
        else {
            throw SupplementalDocumentError.duplicateCoordinateSpace
        }
        guard Set(captureSessionIDs).count
                == captureSessionIDs.count
        else {
            throw SupplementalDocumentError.duplicateCaptureSession
        }
        self.path = path
        self.data = data
        self.declaration = declaration
        self.coordinateSpaceIDs = coordinateSpaceIDs
        self.captureSessionIDs = captureSessionIDs
    }
}
