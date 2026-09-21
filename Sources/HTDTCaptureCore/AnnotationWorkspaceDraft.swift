import Foundation

/// Non-canonical draft of the annotation workspace's staged edits
/// (#266). A draft is app-private scratch state — never written into
/// the capture working set — and is bound to the exact working
/// revision and coordinate space it was authored against. Autosave
/// writes drafts; only the workspace's explicit Save commits canonical
/// `annotations/` authority.
public struct AnnotationWorkspaceDraft: Codable, Sendable, Equatable {
    public static let schema = "htdt.annotation-workspace-draft"
    public static let schemaVersion = "1.0.0"

    public let schemaName: String
    public let schemaVersionValue: String
    public let captureRevisionID: CaptureRevisionID
    public let coordinateSpaceID: CoordinateSpaceID
    public let savedAtUTC: String
    /// Staged (possibly unsaved) annotation entities.
    public var annotations: [CaptureAnnotationEntity]
    /// Staged (possibly unsaved) measurements.
    public var measurements: [CaptureMeasurement]
    /// Staged equipment-identity attestations keyed by the entity they
    /// bind to; committed alongside the canonical collections on Save.
    public var equipmentIdentityRecords: [EquipmentIdentityRecord]
    /// Ordered channel-role plan the speaker-layout flow is running
    /// through, when the operator started one (#278).
    public var speakerLayoutPlan: SpeakerLayoutPlan?

    public init(
        captureRevisionID: CaptureRevisionID,
        coordinateSpaceID: CoordinateSpaceID,
        savedAtUTC: String,
        annotations: [CaptureAnnotationEntity] = [],
        measurements: [CaptureMeasurement] = [],
        equipmentIdentityRecords: [EquipmentIdentityRecord] = [],
        speakerLayoutPlan: SpeakerLayoutPlan? = nil
    ) {
        self.schemaName = Self.schema
        self.schemaVersionValue = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.coordinateSpaceID = coordinateSpaceID
        self.savedAtUTC = savedAtUTC
        self.annotations = annotations
        self.measurements = measurements
        self.equipmentIdentityRecords = equipmentIdentityRecords
        self.speakerLayoutPlan = speakerLayoutPlan
    }

    private enum CodingKeys: String, CodingKey {
        case schemaName = "schema"
        case schemaVersionValue = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case coordinateSpaceID = "coordinate_space_id"
        case savedAtUTC = "saved_at_utc"
        case annotations
        case measurements
        case equipmentIdentityRecords = "equipment_identity_records"
        case speakerLayoutPlan = "speaker_layout_plan"
    }
}

/// App-private draft persistence for the annotation workspace (#266).
/// Files live outside every capture-bundle root so autosave can never
/// mutate or impersonate canonical authority. One draft is kept per
/// working revision; a draft whose recorded revision or coordinate
/// space does not match the caller's binding is discarded rather than
/// applied.
public struct AnnotationWorkspaceDraftStore: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    private func fileURL(
        for revisionID: CaptureRevisionID
    ) -> URL {
        directoryURL.appendingPathComponent(
            "annotation-draft-" + revisionID.description + ".json",
            isDirectory: false
        )
    }

    /// Returns the draft bound to exactly `revisionID` +
    /// `coordinateSpaceID`; a stale-binding or corrupt draft is deleted
    /// and reported as nil so it can never be applied.
    public func load(
        revisionID: CaptureRevisionID,
        coordinateSpaceID: CoordinateSpaceID
    ) -> AnnotationWorkspaceDraft? {
        let url = fileURL(for: revisionID)
        guard let data = try? Data(contentsOf: url),
              let draft = try? JSONDecoder().decode(
                  AnnotationWorkspaceDraft.self,
                  from: data
              )
        else {
            return nil
        }
        guard draft.captureRevisionID == revisionID,
              draft.coordinateSpaceID == coordinateSpaceID
        else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return draft
    }

    public func save(_ draft: AnnotationWorkspaceDraft) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(draft)
        try data.write(
            to: fileURL(for: draft.captureRevisionID),
            options: .atomic
        )
    }

    /// Removes the draft for `revisionID` — on Save, Cancel, discard,
    /// finalization, or coordinate-authority loss. Missing files are
    /// ignored.
    public func discard(revisionID: CaptureRevisionID) {
        try? FileManager.default.removeItem(
            at: fileURL(for: revisionID)
        )
    }

    /// Removes every draft in the store — used on capture reset, when
    /// bound drafts can never become live again.
    public func discardAll() {
        guard let files = try? FileManager.default
            .contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
        else {
            return
        }
        for file in files where file.lastPathComponent
            .hasPrefix("annotation-draft-")
        {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
