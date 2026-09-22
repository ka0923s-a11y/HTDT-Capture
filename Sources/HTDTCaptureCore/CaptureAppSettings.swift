import Foundation

/// Presentation-only length display unit (issue #338, section A).
///
/// Measurements are persisted in canonical `MeasurementUnit` values —
/// `.meter` for length — and this preference only changes how a
/// canonical length is rendered for display. Switching units never
/// rewrites recorded capture bytes or their meaning.
public enum LengthDisplayUnit:
    String,
    Codable,
    Sendable,
    Equatable,
    CaseIterable
{
    case meter = "m"
    case millimeter = "mm"
    case inch = "in"
    case foot = "ft"

    /// Renders a canonical meter length in this display unit. The
    /// value is purely presentational — callers must keep storing the
    /// canonical meter value (#235).
    public func format(lengthMeters: Double) -> String {
        formatValue(lengthMeters: lengthMeters)
            + " " + rawValue
    }

    /// The numeric component only, for compound values (vectors).
    public func formatValue(lengthMeters: Double) -> String {
        switch self {
        case .meter:
            return lengthMeters.formatted(
                .number.precision(.fractionLength(0...2))
            )
        case .millimeter:
            return (lengthMeters * 1000).formatted(
                .number.precision(.fractionLength(0))
            )
        case .inch:
            return (lengthMeters / 0.0254).formatted(
                .number.precision(.fractionLength(0...1))
            )
        case .foot:
            return (lengthMeters / 0.3048).formatted(
                .number.precision(.fractionLength(0...1))
            )
        }
    }
}

/// Operator-selectable backup policy for finalized capture data
/// (issue #305, taxonomy section C).
///
/// Working scan data is always excluded from backup regardless of
/// this policy. `backupEligible` keeps the ADR-0004 default:
/// finalized revisions and exported archives stay in app storage and
/// may be covered by the platform's user-managed backup. The policy
/// is applied to existing finalized artifacts when changed and to
/// every newly promoted revision from then on — it is never recorded
/// inside a capture bundle, so changing it can never reinterpret
/// historical authority.
public enum FinalizedBackupPolicy:
    String,
    Codable,
    Sendable,
    Equatable,
    CaseIterable
{
    /// Finalized revisions and export archives may be included in the
    /// platform's user-managed backup (ADR-0004 default).
    case backupEligible = "backup_eligible"
    /// Finalized revisions and export archives are excluded from
    /// platform backup; explicit Share/Send remains the only way data
    /// leaves the device.
    case excludedFromBackup = "excluded_from_backup"
}

/// A. Presentation preferences (issue #338): UI-only values that
/// never enter capture authority.
public struct CapturePresentationPreferences:
    Codable,
    Sendable,
    Equatable
{
    /// Haptic + VoiceOver announcement cues during scanning (#252).
    public var guidanceCuesEnabled: Bool
    /// Display-only unit for canonical meter lengths (#235).
    public var lengthDisplayUnit: LengthDisplayUnit

    public init(
        guidanceCuesEnabled: Bool = true,
        lengthDisplayUnit: LengthDisplayUnit = .meter
    ) {
        self.guidanceCuesEnabled = guidanceCuesEnabled
        self.lengthDisplayUnit = lengthDisplayUnit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guidanceCuesEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .guidanceCuesEnabled
        ) ?? true
        lengthDisplayUnit = try container.decodeIfPresent(
            LengthDisplayUnit.self,
            forKey: .lengthDisplayUnit
        ) ?? .meter
    }

    private enum CodingKeys: String, CodingKey {
        case guidanceCuesEnabled = "guidance_cues_enabled"
        case lengthDisplayUnit = "length_display_unit"
    }
}

/// B. Device-local workflow defaults (issue #338): values that seed a
/// new capture but are always overridden by an explicit per-capture or
/// project/task selection. The effective value used is recorded into
/// capture authority at the point of use — changing the default later
/// never reinterprets a stored capture.
public struct CaptureWorkflowDefaults:
    Codable,
    Sendable,
    Equatable
{
    /// Identifier of the task profile seeded when a new capture
    /// begins (#217/#259). Nil means no seed: the capture keeps the
    /// operator's explicit selection (or the geometry-only default).
    public var defaultTaskProfileIdentifier: String?
    /// Whether the optional return-to-start consistency check starts
    /// armed for a new scan (#273).
    public var returnToStartCheckEnabled: Bool

    public init(
        defaultTaskProfileIdentifier: String? = nil,
        returnToStartCheckEnabled: Bool = false
    ) {
        self.defaultTaskProfileIdentifier =
            defaultTaskProfileIdentifier
        self.returnToStartCheckEnabled = returnToStartCheckEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultTaskProfileIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .defaultTaskProfileIdentifier
        )
        returnToStartCheckEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .returnToStartCheckEnabled
        ) ?? false
    }

    /// Resolves the stored identifier to a built-in profile. Unknown
    /// identifiers (e.g. a profile added by a later app version)
    /// degrade to nil so a stale default never silently selects the
    /// wrong strategy.
    public var defaultTaskProfile: CaptureTaskProfile? {
        defaultTaskProfileIdentifier.flatMap(
            CaptureTaskProfile.standalonePreset
        )
    }

    private enum CodingKeys: String, CodingKey {
        case defaultTaskProfileIdentifier =
            "default_task_profile_identifier"
        case returnToStartCheckEnabled = "return_to_start_check_enabled"
    }
}

/// C. Storage & privacy preferences (issue #338): device storage
/// behavior. These are never capture semantic authority and never
/// recorded inside annotation records.
public struct CaptureStoragePrivacyPreferences:
    Codable,
    Sendable,
    Equatable
{
    /// Backup policy applied to `finalized/` + `exports/` artifacts
    /// (#305).
    public var finalizedBackupPolicy: FinalizedBackupPolicy

    public init(
        finalizedBackupPolicy: FinalizedBackupPolicy = .backupEligible
    ) {
        self.finalizedBackupPolicy = finalizedBackupPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        finalizedBackupPolicy = try container.decodeIfPresent(
            FinalizedBackupPolicy.self,
            forKey: .finalizedBackupPolicy
        ) ?? .backupEligible
    }

    private enum CodingKeys: String, CodingKey {
        case finalizedBackupPolicy = "finalized_backup_policy"
    }
}

/// Versioned app-local settings document (issue #338). Lives at
/// `<captureRoot>/app-settings.json` — outside `finalized/`,
/// `exports/`, and `working/` — so it is never part of a canonical
/// bundle and never inventoried by `PersistedCaptureInventory`.
///
/// Sections decode independently with per-key defaults, so adding a
/// future section or field never breaks a document written by an
/// older build; `schema`/`schema_version` still gate documents a
/// build genuinely cannot interpret.
public struct CaptureAppSettings: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.app-settings"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public var presentation: CapturePresentationPreferences
    public var captureDefaults: CaptureWorkflowDefaults
    public var storagePrivacy: CaptureStoragePrivacyPreferences

    public init(
        presentation: CapturePresentationPreferences
            = CapturePresentationPreferences(),
        captureDefaults: CaptureWorkflowDefaults
            = CaptureWorkflowDefaults(),
        storagePrivacy: CaptureStoragePrivacyPreferences
            = CaptureStoragePrivacyPreferences()
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.presentation = presentation
        self.captureDefaults = captureDefaults
        self.storagePrivacy = storagePrivacy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        presentation = try container.decodeIfPresent(
            CapturePresentationPreferences.self,
            forKey: .presentation
        ) ?? CapturePresentationPreferences()
        captureDefaults = try container.decodeIfPresent(
            CaptureWorkflowDefaults.self,
            forKey: .captureDefaults
        ) ?? CaptureWorkflowDefaults()
        storagePrivacy = try container.decodeIfPresent(
            CaptureStoragePrivacyPreferences.self,
            forKey: .storagePrivacy
        ) ?? CaptureStoragePrivacyPreferences()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(presentation, forKey: .presentation)
        try container.encode(captureDefaults, forKey: .captureDefaults)
        try container.encode(storagePrivacy, forKey: .storagePrivacy)
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case presentation
        case captureDefaults = "capture_defaults"
        case storagePrivacy = "storage_privacy"
    }
}

public enum CaptureAppSettingsError: Error, Sendable, Equatable {
    case unreadableDocument
    case schemaMismatch
}

/// Reads and writes the app-local settings document. Same atomic
/// temp+replace contract as `CaptureLibraryMetadataStore`: a missing
/// file reads as defaults, a corrupt file fails closed rather than
/// silently dropping operator choices.
public struct CaptureAppSettingsStore: Sendable {
    public let fileURL: URL

    public init(captureRoot: URL) {
        self.fileURL = captureRoot.appendingPathComponent(
            "app-settings.json",
            isDirectory: false
        )
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> CaptureAppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return CaptureAppSettings()
        }
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(
                CaptureAppSettings.self,
                from: data
              )
        else {
            throw CaptureAppSettingsError.unreadableDocument
        }
        guard document.schema == CaptureAppSettings.schema,
              document.schemaVersion
                == CaptureAppSettings.schemaVersion
        else {
            throw CaptureAppSettingsError.schemaMismatch
        }
        return document
    }

    public func save(_ settings: CaptureAppSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
            .prettyPrinted,
        ]
        let data = try encoder.encode(settings)
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let temporary = parent.appendingPathComponent(
            ".tmp-\(UUID().uuidString)"
        )
        do {
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(
                    fileURL,
                    withItemAt: temporary
                )
            } else {
                try FileManager.default.moveItem(
                    at: temporary,
                    to: fileURL
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
