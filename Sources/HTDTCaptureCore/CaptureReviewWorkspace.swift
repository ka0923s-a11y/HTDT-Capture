import Foundation

/// Why a retained evidence frame exists in the capture (issue #241).
/// Surfaced verbatim to the operator during privacy review.
public enum EvidenceRetentionReason: String, Sendable, Equatable {
    /// The frame committed by the End boundary transaction; it is the
    /// scan's closing spatial observation and can only be replaced by
    /// Continue scanning → End again.
    case endBoundary = "end_boundary"
    /// The frame is referenced by at least one committed annotation,
    /// measurement, opening candidate, or the room reference frame.
    case linkedToAuthority = "linked_to_authority"
    /// Operator-saved evidence not referenced by any authority; an
    /// optional visual frame eligible for privacy removal.
    case operatorSaved = "operator_saved"
}

/// One retained evidence frame as presented in the visual evidence
/// review (issue #241) and the Review evidence gallery (issue #213).
public struct ReviewEvidenceItem:
    Sendable,
    Equatable,
    Identifiable
{
    public let frameID: EvidenceFrameID
    /// `evidence/frames/<id>.json` logical path.
    public let descriptorPath: String
    /// `evidence/frames/<id>.pixelbin` logical path.
    public let pixelPath: String
    /// Derived `evidence/frames/<id>.preview.heic` logical path when the
    /// preview payload exists.
    public let previewPath: String?
    /// Absolute URL of the preview payload when present on disk.
    public let previewFileURL: URL?
    /// Total bytes attributable to this frame: descriptor + pixel +
    /// depth + confidence + preview.
    public let byteCount: Int64
    public let sessionTimestampSeconds: Double
    public let coordinateSpaceID: CoordinateSpaceID
    /// Stable tokens naming the authorities that reference this frame
    /// (entity ids, measurement ids, opening source refs, "room_frame").
    public let referencedBy: [String]
    public let retentionReason: EvidenceRetentionReason
    /// True only when the frame is safe to delete: unreferenced and not
    /// the End-boundary observation (issue #241).
    public let removable: Bool

    public init(
        frameID: EvidenceFrameID,
        descriptorPath: String,
        pixelPath: String,
        previewPath: String?,
        previewFileURL: URL?,
        byteCount: Int64,
        sessionTimestampSeconds: Double,
        coordinateSpaceID: CoordinateSpaceID,
        referencedBy: [String],
        retentionReason: EvidenceRetentionReason,
        removable: Bool
    ) {
        self.frameID = frameID
        self.descriptorPath = descriptorPath
        self.pixelPath = pixelPath
        self.previewPath = previewPath
        self.previewFileURL = previewFileURL
        self.byteCount = byteCount
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.coordinateSpaceID = coordinateSpaceID
        self.referencedBy = referencedBy
        self.retentionReason = retentionReason
        self.removable = removable
    }

    public var id: EvidenceFrameID { frameID }
}

/// A platform-independent top-down plan model projected from RoomPlan
/// output plus the operator's openings/frame annotations (issue #213).
/// The view renders it on a SwiftUI `Canvas`; nothing here depends on
/// RoomPlan/UIKit so the model round-trips on macOS for tests.
public struct RoomPlanPreviewModel: Sendable, Equatable {
    /// One projected wall/surface segment or opening marker on the XZ
    /// (floor-plan) plane, meters.
    public struct PlanWall: Sendable, Equatable {
        public let startX: Double
        public let startZ: Double
        public let endX: Double
        public let endZ: Double

        public init(
            startX: Double,
            startZ: Double,
            endX: Double,
            endZ: Double
        ) {
            self.startX = startX
            self.startZ = startZ
            self.endX = endX
            self.endZ = endZ
        }
    }

    public struct PlanMarker: Sendable, Equatable {
        public enum Kind: String, Sendable {
            case door
            case window
            case opening
            case object
            case annotation
            case roomFrameOrigin
            case roomFrameFront
        }

        public let kind: Kind
        public let x: Double
        public let z: Double
        /// Optional facing direction (unit vector on the plan).
        public let dirX: Double?
        public let dirZ: Double?
        public let label: String?

        public init(
            kind: Kind,
            x: Double,
            z: Double,
            dirX: Double? = nil,
            dirZ: Double? = nil,
            label: String? = nil
        ) {
            self.kind = kind
            self.x = x
            self.z = z
            self.dirX = dirX
            self.dirZ = dirZ
            self.label = label
        }
    }

    /// Axis-aligned bounds over all content in meters, XZ plane.
    public let minX: Double
    public let maxX: Double
    public let minZ: Double
    public let maxZ: Double
    public let walls: [PlanWall]
    public let markers: [PlanMarker]

    public init(
        minX: Double,
        maxX: Double,
        minZ: Double,
        maxZ: Double,
        walls: [PlanWall],
        markers: [PlanMarker]
    ) {
        self.minX = minX
        self.maxX = maxX
        self.minZ = minZ
        self.maxZ = maxZ
        self.walls = walls
        self.markers = markers
    }

    public var isEmpty: Bool {
        walls.isEmpty && markers.isEmpty
    }
}

/// The assembled Review/privacy workspace model (issues #213, #231,
/// #232, #241): RoomPlan summary + plan preview, the evidence gallery,
/// committed annotations/measurements, the opening review, and the room
/// reference frame. Built both for the live post-End working set and,
/// read-only, for a persisted finalized bundle (issue #294).
public struct CaptureReviewWorkspaceModel: Sendable, Equatable {
    public let captureRevisionID: CaptureRevisionID
    public let coordinateSpaceID: CoordinateSpaceID?
    /// Canonical RoomPlan capture metadata; nil when the capture has no
    /// RoomPlan lineage.
    public let roomMetadata: CapturedRoomMetadataDocument?
    /// Top-down plan projection; nil when the processed RoomPlan payload
    /// is unavailable or could not be decoded on this platform.
    public let planPreview: RoomPlanPreviewModel?
    public let evidenceItems: [ReviewEvidenceItem]
    public let annotations: [CaptureAnnotationEntity]
    public let measurements: [CaptureMeasurement]
    public let openingReview: OpeningReviewDocument?
    public let roomReferenceFrame: RoomReferenceFrameDocument?
    public let qualityReport: CaptureQualityReport?
    /// True for the persisted-capture viewer (#294): everything
    /// renders read-only.
    public let readOnly: Bool
    /// True when the live capture's spatial authority was sealed for
    /// finalization (issue #276): semantic edits remain allowed but
    /// live spatial capture is unavailable.
    public let spatialCaptureSealed: Bool
    /// Decoding/enumeration problems that degraded the workspace. A
    /// missing optional payload is not an issue; an unreadable declared
    /// payload is listed so the UI can degrade to text while naming
    /// what could not be shown.
    public let issues: [String]

    public init(
        captureRevisionID: CaptureRevisionID,
        coordinateSpaceID: CoordinateSpaceID?,
        roomMetadata: CapturedRoomMetadataDocument?,
        planPreview: RoomPlanPreviewModel?,
        evidenceItems: [ReviewEvidenceItem],
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        openingReview: OpeningReviewDocument?,
        roomReferenceFrame: RoomReferenceFrameDocument?,
        qualityReport: CaptureQualityReport?,
        readOnly: Bool,
        spatialCaptureSealed: Bool,
        issues: [String] = []
    ) {
        self.captureRevisionID = captureRevisionID
        self.coordinateSpaceID = coordinateSpaceID
        self.roomMetadata = roomMetadata
        self.planPreview = planPreview
        self.evidenceItems = evidenceItems
        self.annotations = annotations
        self.measurements = measurements
        self.openingReview = openingReview
        self.roomReferenceFrame = roomReferenceFrame
        self.qualityReport = qualityReport
        self.readOnly = readOnly
        self.spatialCaptureSealed = spatialCaptureSealed
        self.issues = issues
    }
}

/// Assembles `CaptureReviewWorkspaceModel` instances from committed
/// capture bytes. Shared by the post-End Review workspace (working set,
/// issue #213), the visual evidence review (issue #241), and the
/// persisted-capture viewer (issue #294).
public enum CaptureReviewWorkspaceLoader {
    /// Builds the workspace model for a live working set. Frame
    /// descriptors and evidence payloads are read from the declared
    /// payload set of the store snapshot — files that exist on disk but
    /// were never committed are never adopted into review state.
    /// `endBoundaryFrameIDs` marks the frames the current End attempt
    /// committed so the gallery can flag them as non-removable closing
    /// evidence.
    public static func loadWorkingSet(
        snapshot: CaptureWorkingSetSnapshot,
        endBoundaryFrameIDs: Set<EvidenceFrameID> = []
    ) -> CaptureReviewWorkspaceModel {
        loadBundleTree(
            root: snapshot.rootDirectory,
            declaredPaths: Set(
                snapshot.payloadDeclarations.map(\.path)
            ),
            captureRevisionID:
                snapshot.identity.captureRevisionID,
            roomMetadata: snapshot.capturedRoomMetadata,
            endBoundaryFrameIDs: endBoundaryFrameIDs,
            qualityReport: nil,
            readOnly: false,
            spatialCaptureSealed: false
        )
    }

    /// Builds the read-only workspace model for a validated finalized
    /// bundle (issue #294). The manifest's declared file set decides
    /// which payloads are decoded — a byte-verified member only, never
    /// an undeclared extra file.
    public static func loadPersisted(
        directory: URL,
        manifest: BundleManifest
    ) -> CaptureReviewWorkspaceModel {
        loadBundleTree(
            root: directory,
            declaredPaths: Set(manifest.files.map(\.path)),
            captureRevisionID: manifest.captureRevisionID,
            roomMetadata: nil,
            endBoundaryFrameIDs: [],
            qualityReport: nil,
            readOnly: true,
            spatialCaptureSealed: true
        )
    }

    private static func loadBundleTree(
        root: URL,
        declaredPaths: Set<String>,
        captureRevisionID: CaptureRevisionID,
        roomMetadata: CapturedRoomMetadataDocument?,
        endBoundaryFrameIDs: Set<EvidenceFrameID>,
        qualityReport: CaptureQualityReport?,
        readOnly: Bool,
        spatialCaptureSealed: Bool
    ) -> CaptureReviewWorkspaceModel {
        var issues: [String] = []
        let decoder = JSONDecoder()

        func decodeIfDeclared<T: Codable>(
            _ type: T.Type,
            _ path: String
        ) -> T? {
            guard declaredPaths.contains(path) else {
                return nil
            }
            let url = path.split(separator: "/").reduce(root) {
                $0.appendingPathComponent(
                    String($1),
                    isDirectory: false
                )
            }
            guard let data = try? Data(contentsOf: url),
                  let value = try? decoder.decode(T.self, from: data)
            else {
                issues.append("unreadable declared payload: " + path)
                return nil
            }
            return value
        }

        let metadata =
            roomMetadata
            ?? decodeIfDeclared(
                CapturedRoomMetadataDocument.self,
                RoomPlanEvidenceArtifactBuilder.metadataPath
            )
        let annotationCollection = decodeIfDeclared(
            CaptureAnnotationCollection.self,
            AnnotationEvidencePackage.path
        )
        let measurementCollection = decodeIfDeclared(
            CaptureMeasurementCollection.self,
            MeasurementEvidencePackage.path
        )
        let openingReview = decodeIfDeclared(
            OpeningReviewDocument.self,
            OpeningReviewPackage.path
        )
        let roomReferenceFrame = decodeIfDeclared(
            RoomReferenceFrameDocument.self,
            RoomReferenceFramePackage.path
        )
        let quality = qualityReport ?? decodeIfDeclared(
            CaptureQualityReport.self,
            "quality/capture-quality.json"
        )
        let policy = decodeIfDeclared(
            CoordinateSpacePolicyDocument.self,
            CoordinateSpacePolicyPackage.path
        )

        // Frame descriptors are enumerated from the declared set, not
        // from the filesystem listing alone.
        var descriptors: [FrameEvidenceDescriptor] = []
        for path in declaredPaths
            where path.hasPrefix("evidence/frames/")
                && path.hasSuffix(".json")
        {
            if let descriptor: FrameEvidenceDescriptor =
                decodeIfDeclared(
                    FrameEvidenceDescriptor.self,
                    path
                )
            {
                descriptors.append(descriptor)
            }
        }
        descriptors.sort {
            $0.frameID.description < $1.frameID.description
        }

        let evidenceItems = descriptors.map { descriptor in
            buildEvidenceItem(
                descriptor: descriptor,
                root: root,
                declaredPaths: declaredPaths,
                annotations:
                    annotationCollection?.entities ?? [],
                measurements:
                    measurementCollection?.measurements ?? [],
                openings: openingReview?.openings ?? [],
                roomReferenceFrame: roomReferenceFrame,
                endBoundaryFrameIDs: endBoundaryFrameIDs,
                readOnly: readOnly
            )
        }

        let coordinateSpaceID =
            policy?.coordinateSpaceID
            ?? roomReferenceFrame?.coordinateSpaceID
            ?? descriptors.first?.coordinateSpaceID

        return CaptureReviewWorkspaceModel(
            captureRevisionID: captureRevisionID,
            coordinateSpaceID: coordinateSpaceID,
            roomMetadata: metadata,
            planPreview: nil,
            evidenceItems: evidenceItems,
            annotations: annotationCollection?.entities ?? [],
            measurements:
                measurementCollection?.measurements ?? [],
            openingReview: openingReview,
            roomReferenceFrame: roomReferenceFrame,
            qualityReport: quality,
            readOnly: readOnly,
            spatialCaptureSealed: spatialCaptureSealed,
            issues: issues
        )
    }

    /// Resolves which committed authorities reference a frame. A ref
    /// counts when it is `path:evidence/frames/<id>.json`, `path:` to
    /// this frame's pixel path, `frame:<id>`, or `mesh_anchor:` is NOT
    /// counted (mesh refs bind anchors, not frames).
    private static func buildEvidenceItem(
        descriptor: FrameEvidenceDescriptor,
        root: URL,
        declaredPaths: Set<String>,
        annotations: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        openings: [RoomOpeningCandidate],
        roomReferenceFrame: RoomReferenceFrameDocument?,
        endBoundaryFrameIDs: Set<EvidenceFrameID>,
        readOnly: Bool
    ) -> ReviewEvidenceItem {
        let descriptorPath =
            "evidence/frames/" + descriptor.frameID.description
            + ".json"
        let previewPath =
            "evidence/frames/" + descriptor.frameID.description
            + ".preview.heic"
        let previewDeclared = declaredPaths.contains(previewPath)
        let previewURL = previewDeclared
            ? previewPath.split(separator: "/").reduce(root) {
                $0.appendingPathComponent(
                    String($1),
                    isDirectory: false
                )
            }
            : nil

        let frameTokens: Set<String> = [
            "path:" + descriptorPath,
            "path:" + descriptor.pixelRelativePath,
            "frame:" + descriptor.frameID.description,
        ]
        func refsFrame(_ refs: [String]) -> Bool {
            refs.contains { frameTokens.contains($0) }
        }

        var referencedBy: [String] = []
        for entity in annotations {
            let refs =
                entity.evidenceRefs
                + entity.placement.sourceEvidenceRefs
            if refsFrame(refs) {
                referencedBy.append(
                    "entity:" + entity.entityID.description
                )
            }
        }
        for measurement in measurements {
            let refs =
                measurement.evidenceRefs + measurement.endpointRefs
            if refsFrame(refs) {
                referencedBy.append(
                    "measurement:"
                        + measurement.measurementID.description
                )
            }
        }
        for opening in openings where refsFrame(
            opening.evidenceRefs
        ) {
            referencedBy.append(
                "opening:" + opening.sourceRef
            )
        }
        if let frame = roomReferenceFrame,
           refsFrame(frame.evidenceRefs)
        {
            referencedBy.append("room_reference_frame")
        }

        let isEndBoundary =
            endBoundaryFrameIDs.contains(descriptor.frameID)
        let retentionReason: EvidenceRetentionReason
        if isEndBoundary {
            retentionReason = .endBoundary
        } else if !referencedBy.isEmpty {
            retentionReason = .linkedToAuthority
        } else {
            retentionReason = .operatorSaved
        }

        var byteCount: Int64 = 0
        var paths = [descriptorPath, descriptor.pixelRelativePath]
        if let depth = descriptor.depth {
            paths.append(depth.depthRelativePath)
            if let confidencePath = depth.confidenceRelativePath {
                paths.append(confidencePath)
            }
        }
        if previewDeclared {
            paths.append(previewPath)
        }
        for path in paths {
            let url = path.split(separator: "/").reduce(root) {
                $0.appendingPathComponent(
                    String($1),
                    isDirectory: false
                )
            }
            let values = try? url.resourceValues(
                forKeys: [.fileSizeKey]
            )
            byteCount += Int64(values?.fileSize ?? 0)
        }

        return ReviewEvidenceItem(
            frameID: descriptor.frameID,
            descriptorPath: descriptorPath,
            pixelPath: descriptor.pixelRelativePath,
            previewPath: previewDeclared ? previewPath : nil,
            previewFileURL: previewURL,
            byteCount: byteCount,
            sessionTimestampSeconds:
                descriptor.sessionTimestampSeconds,
            coordinateSpaceID: descriptor.coordinateSpaceID,
            referencedBy: referencedBy,
            retentionReason: retentionReason,
            removable: !readOnly
                && !isEndBoundary && referencedBy.isEmpty
        )
    }
}

/// The decoded contents of one persisted bundle directory: the
/// non-binary payloads plus the frame descriptors (issues #221, #294).
/// Produced only for directories that already passed
/// `BundleDirectoryValidator`; the loader never substitutes for that
/// validation.
public struct PersistedCaptureContents: Sendable, Equatable {
    public let manifest: BundleManifest
    public let qualityReport: CaptureQualityReport?
    public let roomMetadata: CapturedRoomMetadataDocument?
    public let sessionDocument: CaptureSessionDocument?
    public let coordinateSpacePolicy: CoordinateSpacePolicyDocument?
    public let entities: [CaptureAnnotationEntity]
    public let measurements: [CaptureMeasurement]
    public let openingReview: OpeningReviewDocument?
    public let roomReferenceFrame: RoomReferenceFrameDocument?
    public let frameDescriptors: [FrameEvidenceDescriptor]
    /// Decoded payloads that were declared but unreadable — surfaced so
    /// the viewer degrades to text instead of hiding the gap.
    public let issues: [String]
    /// The revision's declared intent (`revision/intent.json`) — the
    /// machine-readable added/changed/superseded/reused record diff
    /// for child revisions (#319/#155). Nil on root revisions.
    public let revisionIntent: CaptureRevisionIntentDocument?

    public init(
        manifest: BundleManifest,
        qualityReport: CaptureQualityReport?,
        roomMetadata: CapturedRoomMetadataDocument?,
        sessionDocument: CaptureSessionDocument?,
        coordinateSpacePolicy: CoordinateSpacePolicyDocument?,
        entities: [CaptureAnnotationEntity],
        measurements: [CaptureMeasurement],
        openingReview: OpeningReviewDocument?,
        roomReferenceFrame: RoomReferenceFrameDocument?,
        frameDescriptors: [FrameEvidenceDescriptor],
        issues: [String],
        revisionIntent: CaptureRevisionIntentDocument? = nil
    ) {
        self.manifest = manifest
        self.qualityReport = qualityReport
        self.roomMetadata = roomMetadata
        self.sessionDocument = sessionDocument
        self.coordinateSpacePolicy = coordinateSpacePolicy
        self.entities = entities
        self.measurements = measurements
        self.openingReview = openingReview
        self.roomReferenceFrame = roomReferenceFrame
        self.frameDescriptors = frameDescriptors
        self.issues = issues
        self.revisionIntent = revisionIntent
    }
}

public enum PersistedCaptureContentsLoader {
    /// Decodes the JSON payloads of a validated finalized bundle.
    /// Only manifest-declared paths are read.
    public static func load(
        directory: URL
    ) throws -> PersistedCaptureContents {
        let manifestData = try Data(
            contentsOf: directory.appendingPathComponent(
                "manifest.json",
                isDirectory: false
            )
        )
        let manifest = try JSONDecoder().decode(
            BundleManifest.self,
            from: manifestData
        )
        let declaredPaths = Set(manifest.files.map(\.path))
        let decoder = JSONDecoder()
        var issues: [String] = []

        func decodeIfDeclared<T: Codable>(
            _ type: T.Type,
            _ path: String
        ) -> T? {
            guard declaredPaths.contains(path) else {
                return nil
            }
            let url = path.split(separator: "/").reduce(directory) {
                $0.appendingPathComponent(
                    String($1),
                    isDirectory: false
                )
            }
            guard let data = try? Data(contentsOf: url),
                  let value = try? decoder.decode(T.self, from: data)
            else {
                issues.append("unreadable declared payload: " + path)
                return nil
            }
            return value
        }

        var descriptors: [FrameEvidenceDescriptor] = []
        for path in declaredPaths.sorted()
            where path.hasPrefix("evidence/frames/")
                && path.hasSuffix(".json")
        {
            if let descriptor: FrameEvidenceDescriptor =
                decodeIfDeclared(
                    FrameEvidenceDescriptor.self,
                    path
                )
            {
                descriptors.append(descriptor)
            }
        }

        return PersistedCaptureContents(
            manifest: manifest,
            qualityReport: decodeIfDeclared(
                CaptureQualityReport.self,
                "quality/capture-quality.json"
            ),
            roomMetadata: decodeIfDeclared(
                CapturedRoomMetadataDocument.self,
                RoomPlanEvidenceArtifactBuilder.metadataPath
            ),
            sessionDocument: decodeIfDeclared(
                CaptureSessionDocument.self,
                CaptureSessionFoundationPackage.sessionPath
            ),
            coordinateSpacePolicy: decodeIfDeclared(
                CoordinateSpacePolicyDocument.self,
                CoordinateSpacePolicyPackage.path
            ),
            entities: decodeIfDeclared(
                CaptureAnnotationCollection.self,
                AnnotationEvidencePackage.path
            )?.entities ?? [],
            measurements: decodeIfDeclared(
                CaptureMeasurementCollection.self,
                MeasurementEvidencePackage.path
            )?.measurements ?? [],
            openingReview: decodeIfDeclared(
                OpeningReviewDocument.self,
                OpeningReviewPackage.path
            ),
            roomReferenceFrame: decodeIfDeclared(
                RoomReferenceFrameDocument.self,
                RoomReferenceFramePackage.path
            ),
            frameDescriptors: descriptors,
            issues: issues,
            revisionIntent: decodeIfDeclared(
                CaptureRevisionIntentDocument.self,
                CaptureRevisionIntentPackage.path
            )
        )
    }
}

/// One compared field between a parent and child revision (issue #221).
public struct RevisionFieldComparison: Sendable, Equatable {
    public let field: String
    public let parent: String
    public let child: String
    public let changed: Bool

    public init(
        field: String,
        parent: String,
        child: String
    ) {
        self.field = field
        self.parent = parent
        self.child = child
        self.changed = parent != child
    }
}

/// Metadata-only comparison between a revision and its declared parent
/// (issue #221). The child never inherits spatial coordinates; this
/// comparison is what the operator uses to verify the new scan covered
/// the same room before replacing the parent.
public struct CaptureRevisionComparison: Sendable, Equatable {
    public let parentRevisionID: CaptureRevisionID
    public let childRevisionID: CaptureRevisionID
    public let fields: [RevisionFieldComparison]

    public init(
        parentRevisionID: CaptureRevisionID,
        childRevisionID: CaptureRevisionID,
        fields: [RevisionFieldComparison]
    ) {
        self.parentRevisionID = parentRevisionID
        self.childRevisionID = childRevisionID
        self.fields = fields
    }
}

public enum CaptureRevisionComparator {
    public static func compare(
        parent: PersistedCaptureContents,
        child: PersistedCaptureContents
    ) -> CaptureRevisionComparison {
        func str(_ value: (some BinaryInteger)?) -> String {
            value.map { String(describing: $0) } ?? "—"
        }
        func flag(_ value: Bool?) -> String {
            value.map { $0 ? "yes" : "no" } ?? "—"
        }
        func dims(
            _ metadata: CapturedRoomMetadataDocument?
        ) -> String {
            guard let dims =
                metadata?.summary?.dimensionsMeters
            else {
                return "—"
            }
            return String(
                format: "%.2f × %.2f × %.2f m",
                dims.xMeters, dims.yMeters, dims.zMeters
            )
        }

        // Coordinate-space equality is the spatial carry-forward check:
        // a revision must always observe a fresh space, so identical
        // ids are surfaced rather than hidden.
        let sameSpace =
            parent.manifest.coordinateSpaceIDs
            == child.manifest.coordinateSpaceIDs
        var fields: [RevisionFieldComparison] = [
            RevisionFieldComparison(
                field: "finalized_at",
                parent: parent.manifest.finalizedAtUTC,
                child: child.manifest.finalizedAtUTC
            ),
            RevisionFieldComparison(
                field: "fresh_coordinate_space",
                parent: "—",
                child: sameSpace
                    ? "no — same space id as parent"
                    : "yes"
            ),
        ]
        fields.append(
            RevisionFieldComparison(
                field: "coordinate_space_ids",
                parent: parent.manifest.coordinateSpaceIDs
                    .map(\.description).joined(separator: ", "),
                child: child.manifest.coordinateSpaceIDs
                    .map(\.description).joined(separator: ", ")
            )
        )
        fields.append(
            RevisionFieldComparison(
                field: "roomplan_status",
                parent: parent.qualityReport?.roomPlanStatus.rawValue
                    ?? "—",
                child: child.qualityReport?.roomPlanStatus.rawValue
                    ?? "—"
            )
        )
        fields.append(
            RevisionFieldComparison(
                field: "ready_for_htdt_ingestion",
                parent: flag(
                    parent.qualityReport?.readyForHTDTIngestion
                ),
                child: flag(
                    child.qualityReport?.readyForHTDTIngestion
                )
            )
        )
        fields.append(
            RevisionFieldComparison(
                field: "evidence_frames",
                parent: str(parent.frameDescriptors.count),
                child: str(child.frameDescriptors.count)
            )
        )
        fields.append(
            RevisionFieldComparison(
                field: "mesh_anchors",
                parent: str(
                    parent.qualityReport?.activeMeshAnchorCount
                ),
                child: str(
                    child.qualityReport?.activeMeshAnchorCount
                )
            )
        )
        fields.append(
            RevisionFieldComparison(
                field: "depth_evidence",
                parent: str(
                    parent.qualityReport?.depthEvidenceCount
                ),
                child: str(
                    child.qualityReport?.depthEvidenceCount
                )
            )
        )
        fields.append(
            RevisionFieldComparison(
                field: "annotations",
                parent: str(parent.entities.count),
                child: str(child.entities.count)
            )
        )
        fields.append(
            RevisionFieldComparison(
                field: "measurements",
                parent: str(parent.measurements.count),
                child: str(child.measurements.count)
            )
        )
        fields.append(
            RevisionFieldComparison(
                field: "opening_candidates",
                parent: str(
                    parent.openingReview?.openings.count
                ),
                child: str(
                    child.openingReview?.openings.count
                )
            )
        )
        fields.append(
            RevisionFieldComparison(
                field: "room_reference_frame",
                parent: parent.roomReferenceFrame == nil
                    ? "absent" : "confirmed",
                child: child.roomReferenceFrame == nil
                    ? "absent" : "confirmed"
            )
        )
        fields.append(
            RevisionFieldComparison(
                field: "room_dimensions",
                parent: dims(parent.roomMetadata),
                child: dims(child.roomMetadata)
            )
        )

        // Exact semantic diff (#319): when the child declared a
        // semantic_correction intent, surface the revision kind, the
        // operator's correction note, and the per-record
        // added/changed/superseded/reused accounting — never averaged
        // into the field-level rows above.
        if let intent = child.revisionIntent,
           intent.revisionKind == .semanticCorrection
        {
            fields.append(
                RevisionFieldComparison(
                    field: "revision_kind",
                    parent: "—",
                    child: intent.revisionKind.rawValue
                )
            )
            if let note = intent.correctionNote {
                fields.append(
                    RevisionFieldComparison(
                        field: "correction_note",
                        parent: "—",
                        child: note
                    )
                )
            }
            func recordFields(
                _ refs: [CaptureRevisionRecordRef],
                _ state: String
            ) {
                for ref in refs {
                    fields.append(
                        RevisionFieldComparison(
                            field: ref.payloadPath
                                + " / " + ref.recordID,
                            parent: "—",
                            child: state
                        )
                    )
                }
            }
            recordFields(intent.addedRecordRefs, "added")
            recordFields(intent.changedRecordRefs, "changed")
            recordFields(
                intent.supersededRecordRefs,
                "superseded"
            )
            fields.append(
                RevisionFieldComparison(
                    field: "reused_evidence_refs",
                    parent: "—",
                    child: String(
                        intent.reusedEvidenceRefs.count
                    )
                )
            )
        }
        return CaptureRevisionComparison(
            parentRevisionID: parent.manifest.captureRevisionID,
            childRevisionID: child.manifest.captureRevisionID,
            fields: fields
        )
    }
}
