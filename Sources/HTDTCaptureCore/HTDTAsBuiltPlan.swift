import Foundation

public enum AsBuiltPlanError: Error, Sendable, Equatable {
    case emptyField
    case invalidTimestamp
    case duplicatePlannedEntity
    case unsupportedSchema
}

/// The HTDT-side as-built plan (issue #293, wired by #353): the
/// planned positions the capture is verified against. The plan is
/// workflow input only — its scene-frame coordinates never become
/// capture truth; verification always requires an explicit alignment
/// authority inside the captured coordinate space.
public struct HTDTAsBuiltPlan: Codable, Sendable, Equatable {
    public static let schema = "htdt.as-built-plan"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let planID: String
    public let planVersion: String
    public let projectRef: String
    public let roomName: String
    /// Versioned tolerance policy the plan evaluates deviations under;
    /// nil means deviations are reported without a pass/fail verdict.
    public let tolerancePolicyRef: String?
    public let issuedAtUTC: String?
    public let specs: [PlannedAsBuiltSpec]

    public init(
        planID: String,
        planVersion: String,
        projectRef: String,
        roomName: String,
        tolerancePolicyRef: String? = nil,
        issuedAtUTC: String? = nil,
        specs: [PlannedAsBuiltSpec]
    ) throws {
        let normalizedID = SchemaOwnedText.nfc(planID)
        let normalizedVersion = SchemaOwnedText.nfc(planVersion)
        let normalizedProject = SchemaOwnedText.nfc(projectRef)
        let normalizedRoom = SchemaOwnedText.nfc(roomName)
        guard !normalizedID.isEmpty,
              !normalizedVersion.isEmpty,
              !normalizedProject.isEmpty,
              !normalizedRoom.isEmpty
        else {
            throw AsBuiltPlanError.emptyField
        }
        if let issuedAtUTC {
            guard SchemaTimestampText.isUTCTimestamp(issuedAtUTC)
            else {
                throw AsBuiltPlanError.invalidTimestamp
            }
        }
        guard Set(specs.map(\.plannedEntityID)).count == specs.count
        else {
            throw AsBuiltPlanError.duplicatePlannedEntity
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.planID = normalizedID
        self.planVersion = normalizedVersion
        self.projectRef = normalizedProject
        self.roomName = normalizedRoom
        self.tolerancePolicyRef = SchemaOwnedText.nfc(
            tolerancePolicyRef
        )
        self.issuedAtUTC = issuedAtUTC
        self.specs = specs
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case planID = "plan_id"
        case planVersion = "plan_version"
        case projectRef = "project_ref"
        case roomName = "room_name"
        case tolerancePolicyRef = "tolerance_policy_ref"
        case issuedAtUTC = "issued_at"
        case specs
    }

    /// Decodes an imported plan. Malformed bytes, unsupported schema
    /// versions, and semantic violations all fail closed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == Self.schema,
              schemaVersion == Self.schemaVersion
        else {
            throw AsBuiltPlanError.unsupportedSchema
        }
        try self.init(
            planID: container.decode(String.self, forKey: .planID),
            planVersion: container.decode(
                String.self,
                forKey: .planVersion
            ),
            projectRef: container.decode(
                String.self,
                forKey: .projectRef
            ),
            roomName: container.decode(String.self, forKey: .roomName),
            tolerancePolicyRef: container.decodeIfPresent(
                String.self,
                forKey: .tolerancePolicyRef
            ),
            issuedAtUTC: container.decodeIfPresent(
                String.self,
                forKey: .issuedAtUTC
            ),
            specs: container.decode(
                [PlannedAsBuiltSpec].self,
                forKey: .specs
            )
        )
    }
}

/// The exact imported bytes of an as-built plan plus its identity
/// digest. The session binds plan identity + digest into the
/// persisted `verification/as-built.json` document.
public struct HTDTAsBuiltPlanImport: Sendable, Equatable {
    /// Imported plans persist verbatim into the working set as
    /// imported reference.
    public static let path = "session/as-built-plan.json"

    public let plan: HTDTAsBuiltPlan
    public let data: Data
    public let planSHA256: EvidenceSHA256

    public init(data: Data) throws {
        let plan = try JSONDecoder().decode(
            HTDTAsBuiltPlan.self,
            from: data
        )
        self.plan = plan
        self.data = data
        self.planSHA256 = EvidenceIntegrity.sha256(of: data)
    }
}
