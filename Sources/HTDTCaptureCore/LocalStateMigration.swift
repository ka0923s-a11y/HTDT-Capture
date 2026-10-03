import Foundation

public enum LocalStateMigrationError: Error, Sendable, Equatable {
    /// The document's declared schema or version does not match the
    /// contract the caller required.
    case schemaMismatch
}

/// How losing an app-local durable document would hurt the operator
/// (issue bolph71656-ai/HTDT-Capture#390): drives both migration care and the failure surface
/// the host renders when a document cannot be adopted.
public enum LocalStateCriticality: String, Codable, Sendable {
    /// Names, notes, lifecycle state — canonical captures remain
    /// fully accessible when this cannot be read; bytes are preserved
    /// for recovery and the document is never silently emptied.
    case presentationMetadata = "presentation_metadata"
    /// Mission inbox and the delivery queue — in-flight work depends
    /// on these, so a failed adoption preserves the source bytes and
    /// surfaces an explicit recovery state.
    case operational
    /// Receiver pinning/trust state — fails closed to re-pair; a
    /// failed adoption must never silently drop pinning.
    case trust
}

/// Privacy grouping of the durable document for recovery handling
/// and diagnostics (issue bolph71656-ai/HTDT-Capture#390).
public enum LocalStatePrivacyClass: String, Codable, Sendable {
    case operatorMetadata = "operator_metadata"
    case operationalLedger = "operational_ledger"
    case trustState = "trust_state"
}

/// One schema-owned migration edge: rewrites a supported read-version
/// document's bytes into the next version. The output is validated
/// against the destination contract before it is ever published.
public struct LocalStateMigrationStep: Sendable {
    public let fromVersion: String
    public let toVersion: String
    public let migrate: @Sendable (Data) throws -> Data

    public init(
        fromVersion: String,
        toVersion: String,
        migrate: @escaping @Sendable (Data) throws -> Data
    ) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.migrate = migrate
    }
}

/// One durable app-local document in the schema registry (issue
/// legacy bolph71656-ai/HTDT-Capture#390): which file it lives in, which versions this build reads,
/// and how a supported read version migrates forward.
public struct LocalStateSchema: Sendable {
    public let schemaID: String
    /// File name relative to the capture root.
    public let fileName: String
    /// The version this build writes.
    public let currentVersion: String
    /// Every version this build may still open; anything outside the
    /// set (newer or legacy) is preserved untouched.
    public let supportedReadVersions: [String]
    public let criticality: LocalStateCriticality
    public let privacyClass: LocalStatePrivacyClass
    /// Validates candidate current-version bytes; throws when the
    /// document fails its own contract.
    public let validate: @Sendable (Data) throws -> Void
    /// Edges keyed by the version they migrate from; absent entries
    /// mean no rewrite is registered for that read version.
    public let migrationSteps: [String: LocalStateMigrationStep]

    public init(
        schemaID: String,
        fileName: String,
        currentVersion: String,
        supportedReadVersions: [String],
        criticality: LocalStateCriticality,
        privacyClass: LocalStatePrivacyClass,
        validate: @escaping @Sendable (Data) throws -> Void,
        migrationSteps: [LocalStateMigrationStep] = []
    ) {
        self.schemaID = schemaID
        self.fileName = fileName
        self.currentVersion = currentVersion
        self.supportedReadVersions = supportedReadVersions
        self.criticality = criticality
        self.privacyClass = privacyClass
        self.validate = validate
        self.migrationSteps = Dictionary(
            uniqueKeysWithValues: migrationSteps.map {
                ($0.fromVersion, $0)
            }
        )
    }
}

/// Disposition of one document after the launch-time upgrade pass
/// (issue bolph71656-ai/HTDT-Capture#390). Migration that succeeds is silent by design; the
/// journal still records it so a multi-document upgrade leaves an
/// auditable generation.
public enum LocalStateUpgradeOutcome: String, Codable, Sendable {
    /// An older supported version was rewritten to current and the
    /// result revalidated before the atomic replace.
    case migrated
    /// A version newer than this build writes — the bytes are
    /// preserved untouched and never overwritten.
    case preservedNewerVersion = "preserved_newer_version"
    /// The file could not be read as its declared schema (corrupt,
    /// or a legacy version with no registered step). Bytes are
    /// preserved untouched; nothing is emptied in place.
    case preservedUnreadable = "preserved_unreadable"
    /// A registered step threw or produced bytes that failed the
    /// destination contract; the original file stays in place.
    case migrationFailed = "migration_failed"
}

public struct LocalStateUpgradeEvent:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    /// One launch-time upgrade run shared by every event it emits —
    /// the multi-document generation (legacy bolph71656-ai/HTDT-Capture#390).
    public let upgradeRunID: String
    public let schemaID: String
    public let fileName: String
    public let fromVersion: String
    public let toVersion: String
    public let outcome: LocalStateUpgradeOutcome
    public let appVersion: String
    public let appBuild: String
    public let timestampUTC: String
    /// Path (relative to the capture root) of the pre-migration byte
    /// copy kept for recovery; nil when nothing was rewritten.
    public let recoveryCopyPath: String?
    /// Short operator-safe diagnostic; never raw JSON/schema jargon.
    public let diagnostic: String?

    public var id: String {
        upgradeRunID + "|" + fileName
    }

    public init(
        upgradeRunID: String,
        schemaID: String,
        fileName: String,
        fromVersion: String,
        toVersion: String,
        outcome: LocalStateUpgradeOutcome,
        appVersion: String,
        appBuild: String,
        timestampUTC: String,
        recoveryCopyPath: String? = nil,
        diagnostic: String? = nil
    ) {
        self.upgradeRunID = upgradeRunID
        self.schemaID = schemaID
        self.fileName = fileName
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.outcome = outcome
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.timestampUTC = timestampUTC
        self.recoveryCopyPath = recoveryCopyPath
        self.diagnostic = diagnostic
    }

    private enum CodingKeys: String, CodingKey {
        case upgradeRunID = "upgrade_run_id"
        case schemaID = "schema_id"
        case fileName = "file_name"
        case fromVersion = "from_version"
        case toVersion = "to_version"
        case outcome
        case appVersion = "app_version"
        case appBuild = "app_build"
        case timestampUTC = "timestamp_utc"
        case recoveryCopyPath = "recovery_copy_path"
        case diagnostic
    }
}

/// Versioned wire document for `state-upgrade-journal.json`: the
/// append-only ledger of upgrade-pass outcomes (issue bolph71656-ai/HTDT-Capture#390).
public struct LocalStateUpgradeJournal:
    Codable,
    Sendable,
    Equatable
{
    public static let schema = "htdt.capture.state-upgrade-journal"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public var events: [LocalStateUpgradeEvent]

    public init(events: [LocalStateUpgradeEvent] = []) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case events
    }
}

public struct LocalStateUpgradeReport: Sendable, Equatable {
    /// Every event emitted this run — migrations plus preservations.
    public let events: [LocalStateUpgradeEvent]
    /// Documents whose bytes were preserved rather than adopted:
    /// newer-version or unreadable sources the host must surface
    /// instead of silently emptying.
    public let preserved: [LocalStateUpgradeEvent]

    public init(
        events: [LocalStateUpgradeEvent],
        preserved: [LocalStateUpgradeEvent]
    ) {
        self.events = events
        self.preserved = preserved
    }
}

/// The registry of app-local durable documents the launch pass owns
/// (issue bolph71656-ai/HTDT-Capture#390). Documents are declared with their write version,
/// every version this build may still open, and the migration edges
/// between them; the migrator walks each file exactly once per
/// launch before any store mutates it.
public enum LocalStateSchemaRegistry {
    /// `library-metadata.json` — operator names/notes plus the legacy bolph71656-ai/HTDT-Capture#394
    /// retention lifecycle. v1.0.0 → v1.1.0 adds the `series_states`
    /// and `revision_marks` maps.
    public static let libraryMetadata = LocalStateSchema(
        schemaID: CaptureLibraryMetadataDocument.schema,
        fileName: "library-metadata.json",
        currentVersion: CaptureLibraryMetadataDocument.schemaVersion,
        supportedReadVersions:
            CaptureLibraryMetadataDocument.supportedReadVersions,
        criticality: .presentationMetadata,
        privacyClass: .operatorMetadata,
        validate: { data in
            let document = try JSONDecoder().decode(
                CaptureLibraryMetadataDocument.self,
                from: data
            )
            guard document.schema
                    == CaptureLibraryMetadataDocument.schema,
                  document.schemaVersion
                    == CaptureLibraryMetadataDocument.schemaVersion
            else {
                throw CaptureLibraryMetadataError.schemaMismatch
            }
        },
        migrationSteps: [
            LocalStateMigrationStep(
                fromVersion: "1.0.0",
                toVersion: "1.1.0"
            ) { data in
                // v1.0.0 predates the lifecycle maps; rewrite with the
                // current document contract so `series_states` and
                // `revision_marks` are materialized (empty) under the
                // exact sorted-key writer the store itself uses.
                let legacy = try JSONDecoder().decode(
                    CaptureLibraryMetadataDocument.self,
                    from: data
                )
                guard legacy.schema
                        == CaptureLibraryMetadataDocument.schema,
                      legacy.schemaVersion == "1.0.0"
                else {
                    throw CaptureLibraryMetadataError.schemaMismatch
                }
                let migrated = CaptureLibraryMetadataDocument(
                    series: legacy.series,
                    revisions: legacy.revisions,
                    seriesStates: [:],
                    revisionMarks: [:]
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [
                    .sortedKeys,
                    .withoutEscapingSlashes,
                    .prettyPrinted,
                ]
                return try encoder.encode(migrated)
            }
        ]
    )

    /// `handoff-receipts.json` — the append-only send ledger.
    public static let handoffReceipts = LocalStateSchema(
        schemaID: HTDTHandoffReceiptStore.Document.schema,
        fileName: "handoff-receipts.json",
        currentVersion:
            HTDTHandoffReceiptStore.Document.schemaVersion,
        supportedReadVersions: [
            HTDTHandoffReceiptStore.Document.schemaVersion
        ],
        criticality: .presentationMetadata,
        privacyClass: .operationalLedger,
        validate: { data in
            let document = try JSONDecoder().decode(
                HTDTHandoffReceiptStore.Document.self,
                from: data
            )
            guard document.schema
                    == HTDTHandoffReceiptStore.Document.schema,
                  document.schemaVersion
                    == HTDTHandoffReceiptStore.Document.schemaVersion
            else {
                throw LocalStateMigrationError.schemaMismatch
            }
        }
    )

    /// `mission-inbox.json` — durable mission records.
    public static let missionInbox = LocalStateSchema(
        schemaID: HTDTMissionInboxStore.Document.schema,
        fileName: "mission-inbox.json",
        currentVersion: HTDTMissionInboxStore.Document.schemaVersion,
        supportedReadVersions: [
            HTDTMissionInboxStore.Document.schemaVersion
        ],
        criticality: .operational,
        privacyClass: .operationalLedger,
        validate: { data in
            let document = try JSONDecoder().decode(
                HTDTMissionInboxStore.Document.self,
                from: data
            )
            guard document.schema
                    == HTDTMissionInboxStore.Document.schema,
                  document.schemaVersion
                    == HTDTMissionInboxStore.Document.schemaVersion
            else {
                throw HTDTMissionInboxError.unreadableDocument
            }
        }
    )

    /// `delivery-queue.json` — the durable outbound delivery ledger.
    public static let deliveryQueue = LocalStateSchema(
        schemaID: HTDTDeliveryQueue.Document.schema,
        fileName: "delivery-queue.json",
        currentVersion: HTDTDeliveryQueue.Document.schemaVersion,
        supportedReadVersions: [
            HTDTDeliveryQueue.Document.schemaVersion
        ],
        criticality: .operational,
        privacyClass: .operationalLedger,
        validate: { data in
            let document = try JSONDecoder().decode(
                HTDTDeliveryQueue.Document.self,
                from: data
            )
            guard document.schema
                    == HTDTDeliveryQueue.Document.schema,
                  document.schemaVersion
                    == HTDTDeliveryQueue.Document.schemaVersion
            else {
                throw HTDTDeliveryQueueError.unreadableDocument
            }
        }
    )

    /// `paired-destinations.json` — receiver pinning/trust state;
    /// fails closed to re-pair, never silently unpinned.
    public static let pairedDestinations = LocalStateSchema(
        schemaID: PairedHTDTDestinationStore.Document.schema,
        fileName: "paired-destinations.json",
        currentVersion:
            PairedHTDTDestinationStore.Document.schemaVersion,
        supportedReadVersions: [
            PairedHTDTDestinationStore.Document.schemaVersion
        ],
        criticality: .trust,
        privacyClass: .trustState,
        validate: { data in
            let document = try JSONDecoder().decode(
                PairedHTDTDestinationStore.Document.self,
                from: data
            )
            guard document.schema
                    == PairedHTDTDestinationStore.Document.schema,
                  document.schemaVersion
                    == PairedHTDTDestinationStore.Document.schemaVersion
            else {
                throw HTDTPairingError.unreadableDocument
            }
        }
    )

    public static let documents: [LocalStateSchema] = [
        libraryMetadata,
        handoffReceipts,
        missionInbox,
        deliveryQueue,
        pairedDestinations,
    ]
}

/// Minimal `{schema, schema_version}` envelope used to classify a
/// durable document without committing to its contract (issue bolph71656-ai/HTDT-Capture#390).
private struct LocalStateEnvelope: Decodable {
    let schema: String
    let schemaVersion: String

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
    }
}

/// Numeric `a.b[.c]` comparison for document versions; non-conforming
/// strings never compare as "newer" so they fall into the preserved
/// bucket rather than being treated as an upgrade edge.
private enum LocalStateVersion {
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        guard let a = parts(lhs), let b = parts(rhs) else {
            return false
        }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y {
                return x > y
            }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int]? {
        let pieces = version.split(separator: ".")
        guard !pieces.isEmpty else {
            return nil
        }
        var parsed: [Int] = []
        parsed.reserveCapacity(pieces.count)
        for piece in pieces {
            guard let value = Int(piece), value >= 0 else {
                return nil
            }
            parsed.append(value)
        }
        return parsed
    }
}

/// Launch-time app-local state upgrade pass (issue bolph71656-ai/HTDT-Capture#390). Runs before
/// any store mutates its document: every registered file is
/// classified by its `{schema, schema_version}` envelope and either
/// left alone (current), migrated through its registered edges with
/// retain-old-bytes → temp-write → validate → atomic-replace
/// semantics, or preserved untouched (newer-version or unreadable
/// sources). Every migration and preservation lands in
/// `state-upgrade-journal.json` under one run id so a multi-document
/// upgrade is auditable as a single generation.
public enum LocalStateMigrator {
    public static let journalFileName = "state-upgrade-journal.json"
    public static let recoveryDirectoryName = "state-upgrade-recovery"

    public static func migrate(
        captureRoot: URL,
        appVersion: String,
        appBuild: String,
        nowUTC: String = BundleTimestamp.utcString(from: Date())
    ) -> LocalStateUpgradeReport {
        let fileManager = FileManager.default
        let runID = UUID().uuidString.lowercased()
        var events: [LocalStateUpgradeEvent] = []
        var preserved: [LocalStateUpgradeEvent] = []

        for schema in LocalStateSchemaRegistry.documents {
            let fileURL = captureRoot.appendingPathComponent(
                schema.fileName,
                isDirectory: false
            )
            guard fileManager.fileExists(atPath: fileURL.path) else {
                continue
            }

            func event(
                from: String,
                outcome: LocalStateUpgradeOutcome,
                recovery: String? = nil,
                diagnostic: String? = nil
            ) -> LocalStateUpgradeEvent {
                LocalStateUpgradeEvent(
                    upgradeRunID: runID,
                    schemaID: schema.schemaID,
                    fileName: schema.fileName,
                    fromVersion: from,
                    toVersion: schema.currentVersion,
                    outcome: outcome,
                    appVersion: appVersion,
                    appBuild: appBuild,
                    timestampUTC: nowUTC,
                    recoveryCopyPath: recovery,
                    diagnostic: diagnostic
                )
            }

            guard let data = try? Data(contentsOf: fileURL),
                  let envelope = try? JSONDecoder().decode(
                      LocalStateEnvelope.self,
                      from: data
                  ),
                  envelope.schema == schema.schemaID
            else {
                let outcome = event(
                    from: "unreadable",
                    outcome: .preservedUnreadable,
                    diagnostic:
                        "document could not be read as its declared schema"
                )
                preserved.append(outcome)
                events.append(outcome)
                continue
            }

            let version = envelope.schemaVersion
            if version == schema.currentVersion {
                continue
            }

            // Newer-than-current sources (written by a newer app) are
            // never overwritten: the bytes stay exactly where they are
            // and the host explains the newer-app origin. A version
            // that is not newer but outside the supported read set is
            // an unsupported *older* document — preserved the same
            // way but journaled honestly rather than mislabeled as
            // written by a newer app.
            if LocalStateVersion.isNewer(
                version,
                than: schema.currentVersion
            ) {
                let outcome = event(
                    from: version,
                    outcome: .preservedNewerVersion,
                    diagnostic:
                        "document was written by a newer app version"
                )
                preserved.append(outcome)
                events.append(outcome)
                continue
            }
            if !schema.supportedReadVersions.contains(version) {
                let outcome = event(
                    from: version,
                    outcome: .preservedUnreadable,
                    diagnostic:
                        "document version is outside this build's supported read versions"
                )
                preserved.append(outcome)
                events.append(outcome)
                continue
            }

            // A supported older read version with no registered edge
            // can only be preserved — never rewritten by guessing.
            guard let step = schema.migrationSteps[version],
                  step.toVersion == schema.currentVersion
            else {
                let outcome = event(
                    from: version,
                    outcome: .preservedUnreadable,
                    diagnostic:
                        "no migration step is registered for this version"
                )
                preserved.append(outcome)
                events.append(outcome)
                continue
            }

            do {
                let migratedData = try step.migrate(data)
                // The migrated bytes must satisfy the destination
                // contract before any publish: a step that produces
                // unrecognizable output fails closed.
                try schema.validate(migratedData)

                let recoveryName = retainPreUpgradeCopy(
                    captureRoot: captureRoot,
                    schema: schema,
                    source: fileURL,
                    fromVersion: version
                )

                try replaceAtomically(
                    target: fileURL,
                    data: migratedData
                )
                events.append(
                    event(
                        from: version,
                        outcome: .migrated,
                        recovery: recoveryName
                    )
                )
            } catch {
                let outcome = event(
                    from: version,
                    outcome: .migrationFailed,
                    diagnostic: "migration step failed"
                )
                preserved.append(outcome)
                events.append(outcome)
            }
        }

        if !events.isEmpty {
            appendJournal(
                captureRoot: captureRoot,
                events: events
            )
        }

        return LocalStateUpgradeReport(
            events: events,
            preserved: preserved
        )
    }

    /// Reads the durable upgrade journal; a missing or unreadable
    /// file reads as an empty ledger — the journal is audit, never a
    /// write authority, so it must not block launch.
    public static func journal(
        captureRoot: URL
    ) -> LocalStateUpgradeJournal {
        let url = captureRoot.appendingPathComponent(
            journalFileName,
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: url),
              let journal = try? JSONDecoder().decode(
                  LocalStateUpgradeJournal.self,
                  from: data
              ),
              journal.schema == LocalStateUpgradeJournal.schema
        else {
            return LocalStateUpgradeJournal()
        }
        return journal
    }

    /// Copies the pre-migration bytes into the bounded recovery
    /// directory so the original document can always be restored by
    /// hand; returns the recovery path relative to the capture root.
    private static func retainPreUpgradeCopy(
        captureRoot: URL,
        schema: LocalStateSchema,
        source: URL,
        fromVersion: String
    ) -> String? {
        let fileManager = FileManager.default
        let directory = captureRoot.appendingPathComponent(
            recoveryDirectoryName,
            isDirectory: true
        )
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let name = schema.fileName + ".pre-" + fromVersion
        let target = directory.appendingPathComponent(
            name,
            isDirectory: false
        )
        do {
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: source, to: target)
            return recoveryDirectoryName + "/" + name
        } catch {
            return nil
        }
    }

    /// Validated temp + atomic replace: the migrated bytes are
    /// written to a sibling temp file and moved over the original
    /// only after the write completes, so an interrupted upgrade can
    /// never leave a half-written document (legacy bolph71656-ai/HTDT-Capture#390).
    private static func replaceAtomically(
        target: URL,
        data: Data
    ) throws {
        let parent = target.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(
            ".tmp-\(UUID().uuidString)"
        )
        do {
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(
                    target,
                    withItemAt: temporary
                )
            } else {
                try FileManager.default.moveItem(
                    at: temporary,
                    to: target
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func appendJournal(
        captureRoot: URL,
        events: [LocalStateUpgradeEvent]
    ) {
        var journal = self.journal(captureRoot: captureRoot)
        journal.events.append(contentsOf: events)
        let url = captureRoot.appendingPathComponent(
            journalFileName,
            isDirectory: false
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
            .prettyPrinted,
        ]
        guard let data = try? encoder.encode(journal) else {
            return
        }
        try? replaceAtomically(target: url, data: data)
    }
}
