import Foundation

/// What the operator can inspect about a failed capture's retained
/// working set (issue #224): an enumeration of every retained payload
/// with byte sizes, plus opportunistically decoded JSON authority so
/// the report names the session/coordinate space and committed
/// annotation counts without pretending the failed set is resumable.
public struct FailedCaptureInspection: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let relativePath: String
        public let byteCount: Int64

        public init(relativePath: String, byteCount: Int64) {
            self.relativePath = relativePath
            self.byteCount = byteCount
        }
    }

    public let captureRevisionID: CaptureRevisionID?
    public let failureCode: CaptureFailureCode?
    public let rootDirectory: URL
    public let entries: [Entry]
    /// Decoded committed state, when present: session/captures ids,
    /// committed annotation and measurement counts, whether an End
    /// boundary was accepted (timing/roomplan payloads exist), and the
    /// store's quality/resource events when the host can still
    /// evaluate them.
    public let sessionDocument: CaptureSessionDocument?
    public let coordinateSpacePolicy: CoordinateSpacePolicyDocument?
    public let entityCount: Int?
    public let measurementCount: Int?
    public let frameDescriptorCount: Int
    public let endBoundaryCommitted: Bool
    public let resourceEvents: [CaptureResourceEvent]
    public let enumerationFailures: [String]

    public init(
        captureRevisionID: CaptureRevisionID?,
        failureCode: CaptureFailureCode?,
        rootDirectory: URL,
        entries: [Entry],
        sessionDocument: CaptureSessionDocument?,
        coordinateSpacePolicy: CoordinateSpacePolicyDocument?,
        entityCount: Int?,
        measurementCount: Int?,
        frameDescriptorCount: Int,
        endBoundaryCommitted: Bool,
        resourceEvents: [CaptureResourceEvent],
        enumerationFailures: [String] = []
    ) {
        self.captureRevisionID = captureRevisionID
        self.failureCode = failureCode
        self.rootDirectory = rootDirectory
        self.entries = entries
        self.sessionDocument = sessionDocument
        self.coordinateSpacePolicy = coordinateSpacePolicy
        self.entityCount = entityCount
        self.measurementCount = measurementCount
        self.frameDescriptorCount = frameDescriptorCount
        self.endBoundaryCommitted = endBoundaryCommitted
        self.resourceEvents = resourceEvents
        self.enumerationFailures = enumerationFailures
    }

    public var totalByteCount: Int64 {
        entries.reduce(0) { $0 + $1.byteCount }
    }
}

/// Enumerates and decodes a failed capture's retained working set
/// without resuming it (issue #224). The inspection is observational:
/// it never mutates the working directory and never re-adopts the
/// abandoned coordinate authority.
public enum FailedCaptureInspector {
    public static func inspect(
        workingSetRoot: URL,
        captureRevisionID: CaptureRevisionID?,
        failureCode: CaptureFailureCode?,
        resourceEvents: [CaptureResourceEvent] = [],
        maxEntries: Int = 512
    ) -> FailedCaptureInspection {
        var entries: [FailedCaptureInspection.Entry] = []
        var failures: [String] = []

        if let enumerator = FileManager.default.enumerator(
            at: workingSetRoot,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .isRegularFileKey,
            ],
            options: [.skipsHiddenFiles]
        ) {
            for case let file as URL in enumerator {
                guard entries.count < maxEntries else {
                    failures.append(
                        "inspection truncated at \(maxEntries) entries"
                    )
                    break
                }
                let values = try? file.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey]
                )
                guard values?.isRegularFile == true else {
                    continue
                }
                let rootPath =
                    workingSetRoot.standardizedFileURL.path
                var relative =
                    file.standardizedFileURL.path
                if relative.hasPrefix(rootPath + "/") {
                    relative = String(
                        relative.dropFirst(rootPath.count + 1)
                    )
                }
                entries.append(
                    FailedCaptureInspection.Entry(
                        relativePath: relative,
                        byteCount: Int64(values?.fileSize ?? 0)
                    )
                )
            }
        } else {
            failures.append("working set root could not be enumerated")
        }
        entries.sort { $0.relativePath < $1.relativePath }

        let decoder = JSONDecoder()
        func decode<T: Codable>(_ type: T.Type, _ path: String)
            -> T?
        {
            let url = path.split(separator: "/").reduce(
                workingSetRoot
            ) {
                $0.appendingPathComponent(
                    String($1),
                    isDirectory: false
                )
            }
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try? decoder.decode(T.self, from: data)
        }

        let session: CaptureSessionDocument? = decode(
            CaptureSessionDocument.self,
            CaptureSessionFoundationPackage.sessionPath
        )
        let policy: CoordinateSpacePolicyDocument? = decode(
            CoordinateSpacePolicyDocument.self,
            CoordinateSpacePolicyPackage.path
        )
        let annotations = decode(
            CaptureAnnotationCollection.self,
            AnnotationEvidencePackage.path
        )
        let measurements = decode(
            CaptureMeasurementCollection.self,
            MeasurementEvidencePackage.path
        )
        let frameCount = entries.filter {
            $0.relativePath.hasPrefix("evidence/frames/")
                && $0.relativePath.hasSuffix(".json")
        }.count
        let endCommitted = entries.contains {
            $0.relativePath == CaptureTimingPackage.path
        }

        return FailedCaptureInspection(
            captureRevisionID: captureRevisionID,
            failureCode: failureCode,
            rootDirectory: workingSetRoot,
            entries: entries,
            sessionDocument: session,
            coordinateSpacePolicy: policy,
            entityCount: annotations?.entities.count,
            measurementCount: measurements?.measurements.count,
            frameDescriptorCount: frameCount,
            endBoundaryCommitted: endCommitted,
            resourceEvents: resourceEvents,
            enumerationFailures: failures
        )
    }
}

/// A diagnostic report is NOT a capture bundle: it deliberately uses a
/// different schema name and contains no pixel/depth/mesh payload
/// bytes, only the inspection listing and decoded metadata needed to
/// triage a failure (issue #224).
public struct CaptureDiagnosticReport: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.diagnostic-report"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let generatedAtUTC: String
    public let captureRevisionID: String?
    public let failureCode: String?
    public let retainedEntries: [Entry]
    public let totalByteCount: Int64
    public let captureSessionID: String?
    public let coordinateSpaceID: String?
    public let entityCount: Int?
    public let measurementCount: Int?
    public let frameDescriptorCount: Int
    public let endBoundaryCommitted: Bool
    public let resourceEvents: [CaptureResourceEvent]
    public let enumerationFailures: [String]

    public struct Entry: Codable, Sendable, Equatable {
        public let path: String
        public let bytes: Int64

        public init(path: String, bytes: Int64) {
            self.path = path
            self.bytes = bytes
        }
    }

    public init(inspection: FailedCaptureInspection) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.generatedAtUTC = BundleTimestamp.utcString(
            from: Date()
        )
        self.captureRevisionID =
            inspection.captureRevisionID?.description
        self.failureCode = inspection.failureCode?.rawValue
        self.retainedEntries = inspection.entries.map {
            Entry(path: $0.relativePath, bytes: $0.byteCount)
        }
        self.totalByteCount = inspection.totalByteCount
        self.captureSessionID =
            inspection.sessionDocument?.captureSessionID
                .description
        self.coordinateSpaceID =
            inspection.sessionDocument?.coordinateSpaceID
                .description
            ?? inspection.coordinateSpacePolicy?.coordinateSpaceID
                .description
        self.entityCount = inspection.entityCount
        self.measurementCount = inspection.measurementCount
        self.frameDescriptorCount =
            inspection.frameDescriptorCount
        self.endBoundaryCommitted =
            inspection.endBoundaryCommitted
        self.resourceEvents = inspection.resourceEvents
        self.enumerationFailures =
            inspection.enumerationFailures
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case generatedAtUTC = "generated_at"
        case captureRevisionID = "capture_revision_id"
        case failureCode = "failure_code"
        case retainedEntries = "retained_entries"
        case totalByteCount = "total_byte_count"
        case captureSessionID = "capture_session_id"
        case coordinateSpaceID = "coordinate_space_id"
        case entityCount = "entity_count"
        case measurementCount = "measurement_count"
        case frameDescriptorCount = "frame_descriptor_count"
        case endBoundaryCommitted = "end_boundary_committed"
        case resourceEvents = "resource_events"
        case enumerationFailures = "enumeration_failures"
    }
}

public enum CaptureDiagnosticPackageError:
    Error,
    Sendable,
    Equatable
{
    case unsafeDestination
}

/// Writes the diagnostic package (issue #224). The package lands in a
/// dedicated `diagnostics/` sibling of `finalized/`, `exports/`, and
/// `working/` — never inside the inventoried roots — so it cannot be
/// mistaken for a canonical export and cannot be quarantined as an
/// unrecognized export artifact.
public enum CaptureDiagnosticPackageWriter {
    public static func diagnosticsDirectory(
        captureRoot: URL
    ) -> URL {
        captureRoot.appendingPathComponent(
            "diagnostics",
            isDirectory: true
        )
    }

    /// Writes `<captureRoot>/diagnostics/<stem>.json` and returns the
    /// URL. `stem` is sanitized to a filename-safe token (the caller
    /// normally passes the revision id or orphan directory name).
    public static func write(
        inspection: FailedCaptureInspection,
        captureRoot: URL,
        stem: String
    ) throws -> URL {
        let sanitized = String(
            stem.map {
                $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
                    ? $0 : "-"
            }
        )
        guard !sanitized.isEmpty else {
            throw CaptureDiagnosticPackageError.unsafeDestination
        }

        let report = CaptureDiagnosticReport(
            inspection: inspection
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
            .prettyPrinted,
        ]
        let data = try encoder.encode(report)

        let directory = diagnosticsDirectory(
            captureRoot: captureRoot
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let destination = directory.appendingPathComponent(
            sanitized + ".diagnostic.json",
            isDirectory: false
        )
        let temporary = directory.appendingPathComponent(
            ".tmp-\(UUID().uuidString)"
        )
        do {
            try data.write(to: temporary)
            if FileManager.default.fileExists(
                atPath: destination.path
            ) {
                _ = try FileManager.default.replaceItemAt(
                    destination,
                    withItemAt: temporary
                )
            } else {
                try FileManager.default.moveItem(
                    at: temporary,
                    to: destination
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return destination
    }
}
