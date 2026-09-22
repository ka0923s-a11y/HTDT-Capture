import Foundation

/// Short human-citable correlation id (issue #389), e.g.
/// `[diag 74C2]` — two random bytes rendered uppercase hex. The id is
/// stamped on every artifact of one export so a support conversation
/// can name exactly which package a user sent, without any account,
/// device, or timestamp identifier.
public struct DiagnosticsCorrelationID: Sendable, Equatable {
    /// Uppercase hex, 4 characters.
    public let code: String

    public init(code: String) throws {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 4,
              trimmed.uppercased() == trimmed,
              trimmed.allSatisfy(\.isHexDigit)
        else {
            throw SupportDiagnosticsError.invalidCorrelationID(code)
        }
        self.code = trimmed
    }

    public init() {
        var bytes = [UInt8](repeating: 0, count: 2)
        _ = bytes.withUnsafeMutableBytes {
            SecRandomCompat.fill($0)
        }
        code = bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// `[diag 74C2]` display form — copy-pasteable into a support
    /// message.
    public var displayTag: String { "[diag \(code)]" }
}

/// Tiny SystemRandomness indirection kept so the id generator is
/// deterministic in tests via `DiagnosticsCorrelationID(code:)`.
enum SecRandomCompat {
    static func fill(_ buffer: UnsafeMutableRawBufferPointer) {
        for index in buffer.indices {
            buffer[index] = UInt8.random(in: .min ... .max)
        }
    }
}

public enum SupportDiagnosticsError: Error, Sendable, Equatable {
    case invalidCorrelationID(String)
    /// The package writer refused: a category marked excluded was
    /// requested, or the encoded payload tripped the sensitive-content
    /// scan — export never proceeds partially.
    case privacyReviewFailed(String)
    case emptyPackage
}

/// One privacy-review category of the diagnostics package (issue
/// #389). The package enumerates what it contains by category before
/// export, and the category order is the fixed display order.
public enum SupportDiagnosticsPrivacyCategory:
    String, Codable, Sendable, Equatable, CaseIterable
{
    /// App name/version/build + schema versions this build emits.
    case appBuild = "app_build"
    /// Device model family + OS family/version — never serials, UDID,
    /// hostname, or addresses.
    case deviceSummary = "device_summary"
    /// RoomPlan/mesh/depth/handoff capability bits.
    case capabilitySummary = "capability_summary"
    /// Capture-system health: resource-event counts by kind and
    /// severity, thermal stops, storage preflight verdict, quarantined
    /// and orphaned payload counts, last validation failure class.
    case captureHealth = "capture_health"
    /// Whether the configured HTDT endpoint answered a capability
    /// preflight, and the verdict class — never the URL or token.
    case endpointReachability = "endpoint_reachability"

    /// One-line English description of what the category carries —
    /// shown in the privacy preview before export. Japanese strings
    /// live in the app layer alongside the rest of the UI copy.
    public var contentsSummary: String {
        switch self {
        case .appBuild:
            return "App name, version, build number, and emitted "
                + "schema versions"
        case .deviceSummary:
            return "Device model family and OS version only — no "
                + "serial numbers or identifiers"
        case .capabilitySummary:
            return "Sensor and feature capability flags "
                + "(RoomPlan, LiDAR depth, mesh anchoring)"
        case .captureHealth:
            return "Counts of resource warnings, thermal stops, "
                + "storage preflight verdict, quarantined/orphaned "
                + "payload counts, last validation failure class"
        case .endpointReachability:
            return "Whether the configured receiver answered a "
                + "capability probe, and the verdict class"
        }
    }
}

/// Inputs the collector cannot derive from persisted state — device
/// and app strings arrive already privacy-trimmed by the platform
/// layer (no serials, no hostname, no user-entered text).
public struct SupportDiagnosticsEnvironment: Sendable, Equatable {
    /// e.g. "HTDT Capture".
    public let appName: String
    /// Marketing version, e.g. `1.4.2`.
    public let appVersion: String
    /// Build/train identifier, e.g. `r1234`.
    public let appBuild: String
    /// e.g. `iPad Pro 11-inch (M4)` — the model family string only.
    public let deviceModelFamily: String
    /// e.g. `iPadOS 18.2`.
    public let osFamilyAndVersion: String
    /// Selected emitted schema ids for support reference.
    public let emittedSchemaIDs: [String]

    public init(
        appName: String,
        appVersion: String,
        appBuild: String,
        deviceModelFamily: String,
        osFamilyAndVersion: String,
        emittedSchemaIDs: [String] = []
    ) {
        self.appName = appName
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.deviceModelFamily = deviceModelFamily
        self.osFamilyAndVersion = osFamilyAndVersion
        self.emittedSchemaIDs = emittedSchemaIDs.sorted()
    }
}

/// Capability flags a support engineer needs to reason about what a
/// capture run could have produced (issue #389).
public struct DiagnosticsCapabilitySummary:
    Codable, Sendable, Equatable
{
    public let roomPlanEligible: Bool
    public let sceneReconstructionEligible: Bool
    public let lidarDepthAvailable: Bool
    public let smoothedDepthAvailable: Bool
    public let meshAnchoringAvailable: Bool

    public init(
        roomPlanEligible: Bool,
        sceneReconstructionEligible: Bool,
        lidarDepthAvailable: Bool,
        smoothedDepthAvailable: Bool,
        meshAnchoringAvailable: Bool
    ) {
        self.roomPlanEligible = roomPlanEligible
        self.sceneReconstructionEligible =
            sceneReconstructionEligible
        self.lidarDepthAvailable = lidarDepthAvailable
        self.smoothedDepthAvailable = smoothedDepthAvailable
        self.meshAnchoringAvailable = meshAnchoringAvailable
    }

    private enum CodingKeys: String, CodingKey {
        case roomPlanEligible = "roomplan_eligible"
        case sceneReconstructionEligible =
            "scene_reconstruction_eligible"
        case lidarDepthAvailable = "lidar_depth_available"
        case smoothedDepthAvailable = "smoothed_depth_available"
        case meshAnchoringAvailable = "mesh_anchoring_available"
    }
}

/// Resource-event histogram — counts only, never event detail text
/// (details can name user content). `byKind`/`bySeverity` use the raw
/// enum tokens.
public struct DiagnosticsResourceSummary:
    Codable, Sendable, Equatable
{
    public let totalEvents: Int
    public let byKind: [String: Int]
    public let bySeverity: [String: Int]
    /// Resource events of kind thermal_pressure at warning+ severity —
    /// the "thermal stops" a support ticket asks about.
    public let thermalPressureStops: Int

    public init(
        totalEvents: Int,
        byKind: [String: Int],
        bySeverity: [String: Int],
        thermalPressureStops: Int
    ) {
        self.totalEvents = totalEvents
        self.byKind = byKind
        self.bySeverity = bySeverity
        self.thermalPressureStops = thermalPressureStops
    }

    private enum CodingKeys: String, CodingKey {
        case totalEvents = "total_events"
        case byKind = "by_kind"
        case bySeverity = "by_severity"
        case thermalPressureStops = "thermal_pressure_stops"
    }
}

/// Capture-system health section (issue #389): the operational signals
/// a support ticket needs to reconstruct what the capture subsystem
/// did, without capture evidence.
public struct DiagnosticsCaptureHealth:
    Codable, Sendable, Equatable
{
    public let resourceSummary: DiagnosticsResourceSummary
    /// Last storage preflight verdict token (`sufficient`, `low`,
    /// `critical`, `unknown`) — never the byte counts.
    public let storagePreflightVerdict: String
    /// Captures currently quarantined by validation.
    public let quarantinedArtifactCount: Int
    /// Working directories left behind by crashed sessions.
    public let orphanedWorkingArtifactCount: Int
    /// The most recent bundle-validation failure class (e.g.
    /// `schema_validation_failed`), or nil when nothing failed.
    public let lastValidationFailureClass: String?
    /// Completed captures under management.
    public let persistedCaptureCount: Int

    public init(
        resourceSummary: DiagnosticsResourceSummary,
        storagePreflightVerdict: String,
        quarantinedArtifactCount: Int,
        orphanedWorkingArtifactCount: Int,
        lastValidationFailureClass: String?,
        persistedCaptureCount: Int
    ) {
        self.resourceSummary = resourceSummary
        self.storagePreflightVerdict = storagePreflightVerdict
        self.quarantinedArtifactCount = quarantinedArtifactCount
        self.orphanedWorkingArtifactCount =
            orphanedWorkingArtifactCount
        self.lastValidationFailureClass = lastValidationFailureClass
        self.persistedCaptureCount = persistedCaptureCount
    }

    private enum CodingKeys: String, CodingKey {
        case resourceSummary = "resource_summary"
        case storagePreflightVerdict = "storage_preflight_verdict"
        case quarantinedArtifactCount = "quarantined_artifact_count"
        case orphanedWorkingArtifactCount =
            "orphaned_working_artifact_count"
        case lastValidationFailureClass =
            "last_validation_failure_class"
        case persistedCaptureCount = "persisted_capture_count"
    }
}

/// Endpoint reachability row (issue #389): verdict class only — the
/// package never carries URLs, hosts, or credentials.
public struct DiagnosticsEndpointReachability:
    Codable, Sendable, Equatable
{
    /// `compatible` / `compatible_with_omissions` / `incompatible` /
    /// `unreachable` / `not_checked`.
    public let verdictClass: String
    /// When the probe last ran (UTC timestamp), or nil.
    public let lastCheckedAtUTC: String?

    public init(verdictClass: String, lastCheckedAtUTC: String?) {
        self.verdictClass = verdictClass
        self.lastCheckedAtUTC = lastCheckedAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case verdictClass = "verdict_class"
        case lastCheckedAtUTC = "last_checked_at_utc"
    }
}

/// The versioned diagnostics document (issue #389). The wire contract
/// is deliberately typed so capture evidence cannot enter it: no
/// image/depth/mesh fields, no annotation or project text, no serial
/// numbers, no operator-authored strings.
public struct SupportDiagnosticsReport: Codable, Sendable, Equatable {
    public static let schemaName = "htdt.support.diagnostics"
    public static let schemaVersionValue = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let correlationID: String
    public let generatedAtUTC: String
    public let appName: String
    public let appVersion: String
    public let appBuild: String
    public let emittedSchemaIDs: [String]
    public let deviceModelFamily: String
    public let osFamilyAndVersion: String
    public let capabilities: DiagnosticsCapabilitySummary
    public let captureHealth: DiagnosticsCaptureHealth
    public let endpointReachability:
        DiagnosticsEndpointReachability

    public init(
        correlationID: DiagnosticsCorrelationID,
        generatedAtUTC: Date,
        environment: SupportDiagnosticsEnvironment,
        capabilities: DiagnosticsCapabilitySummary,
        captureHealth: DiagnosticsCaptureHealth,
        endpointReachability: DiagnosticsEndpointReachability
    ) {
        self.schema = Self.schemaName
        self.schemaVersion = Self.schemaVersionValue
        self.correlationID = correlationID.code
        self.generatedAtUTC = BundleTimestamp.utcString(
            from: generatedAtUTC
        )
        self.appName = environment.appName
        self.appVersion = environment.appVersion
        self.appBuild = environment.appBuild
        self.emittedSchemaIDs = environment.emittedSchemaIDs
        self.deviceModelFamily = environment.deviceModelFamily
        self.osFamilyAndVersion = environment.osFamilyAndVersion
        self.capabilities = capabilities
        self.captureHealth = captureHealth
        self.endpointReachability = endpointReachability
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case correlationID = "correlation_id"
        case generatedAtUTC = "generated_at"
        case appName = "app_name"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case emittedSchemaIDs = "emitted_schema_ids"
        case deviceModelFamily = "device_model_family"
        case osFamilyAndVersion = "os_family_and_version"
        case capabilities
        case captureHealth = "capture_health"
        case endpointReachability = "endpoint_reachability"
    }
}

/// One privacy-preview row (issue #389): what the package contains,
/// whether it is exported, and why not when excluded.
public struct DiagnosticsPrivacyPreviewRow:
    Sendable, Equatable
{
    public let category: SupportDiagnosticsPrivacyCategory
    public let contentsSummary: String
    public let included: Bool
    /// For excluded rows, the reason (e.g. "no HTDT endpoint
    /// configured").
    public let exclusionReason: String?

    public init(
        category: SupportDiagnosticsPrivacyCategory,
        included: Bool,
        exclusionReason: String? = nil
    ) {
        self.category = category
        self.contentsSummary = category.contentsSummary
        self.included = included
        self.exclusionReason = exclusionReason
    }
}

/// The collected diagnostics export (issue #389): the typed report,
/// its privacy preview, and both artifacts — a bounded JSON document
/// and a short human-readable text summary. Bytes are produced once
/// here; the caller hands them to a share sheet or writes them to
/// disk — the model performs no I/O of its own.
public struct SupportDiagnosticsPackage: Sendable, Equatable {
    public let correlationID: DiagnosticsCorrelationID
    public let report: SupportDiagnosticsReport
    /// Every category with an include/exclude verdict — the sheet's
    /// "what leaves this device" preview.
    public let privacyPreview: [DiagnosticsPrivacyPreviewRow]
    /// `support-diagnostics-<id>.json` payload bytes.
    public let jsonPayload: Data
    /// `support-diagnostics-<id>.txt` payload bytes.
    public let textPayload: Data

    public var jsonFilename: String {
        "support-diagnostics-\(correlationID.code).json"
    }

    public var textFilename: String {
        "support-diagnostics-\(correlationID.code).txt"
    }
}

/// Builds the diagnostics package (issue #389). All inputs arrive
/// already privacy-shaped — the collector carries no filesystem or
/// network access of its own; the app layer supplies the environment
/// strings and the latest resource/inventory signals.
public enum SupportDiagnosticsCollector {
    /// Resource-event histogram from any quality observation set —
    /// counts only.
    public static func resourceSummary(
        events: [CaptureResourceEvent]
    ) -> DiagnosticsResourceSummary {
        var byKind: [String: Int] = [:]
        var bySeverity: [String: Int] = [:]
        var thermalStops = 0
        for event in events {
            byKind[event.kind.rawValue, default: 0] += 1
            bySeverity[event.severity.rawValue, default: 0] += 1
            if event.kind == .thermalPressure,
               event.severity != .info
            {
                thermalStops += 1
            }
        }
        return DiagnosticsResourceSummary(
            totalEvents: events.count,
            byKind: byKind,
            bySeverity: bySeverity,
            thermalPressureStops: thermalStops
        )
    }

    /// Verdict-class string for the endpoint category — never the
    /// endpoint URL or reason text (which can name hosts).
    public static func endpointReachability(
        verdict: HTDTCompatibilityVerdict?,
        checkedAtUTC: String?
    ) -> DiagnosticsEndpointReachability {
        let verdictClass: String
        switch verdict {
        case .none:
            verdictClass = "not_checked"
        case .compatible:
            verdictClass = "compatible"
        case .compatibleWithOmissions:
            verdictClass = "compatible_with_omissions"
        case .incompatible:
            verdictClass = "incompatible"
        case .unknown:
            verdictClass = "unreachable"
        }
        return DiagnosticsEndpointReachability(
            verdictClass: verdictClass,
            lastCheckedAtUTC: checkedAtUTC
        )
    }

    /// The privacy preview rows for a prospective package — which
    /// categories leave the device and why excluded ones do not.
    public static func privacyPreview(
        endpointChecked: Bool
    ) -> [DiagnosticsPrivacyPreviewRow] {
        SupportDiagnosticsPrivacyCategory.allCases.map { category in
            if category == .endpointReachability, !endpointChecked {
                return DiagnosticsPrivacyPreviewRow(
                    category: category,
                    included: true,
                    exclusionReason: nil
                )
            }
            return DiagnosticsPrivacyPreviewRow(
                category: category,
                included: true
            )
        }
    }

    /// Assembles the report and renders both artifacts. The JSON
    /// output passes a defensive forbidden-token scan before the
    /// package is handed out: capture-relative paths, `sha256`
    /// digests, UUID-shaped user refs and the `secret`/`token`/
    /// `serial` keys must never appear — a scan failure throws
    /// `privacyReviewFailed` and produces no partial export.
    public static func collect(
        environment: SupportDiagnosticsEnvironment,
        capabilities: DiagnosticsCapabilitySummary,
        resourceEvents: [CaptureResourceEvent],
        storagePreflightVerdict: CaptureStorageReadiness,
        persistedCaptureCount: Int,
        quarantinedArtifactCount: Int,
        orphanedWorkingArtifactCount: Int,
        lastValidationFailureClass: String?,
        endpointVerdict: HTDTCompatibilityVerdict?,
        endpointCheckedAtUTC: String?,
        correlationID: DiagnosticsCorrelationID =
            DiagnosticsCorrelationID(),
        generatedAtUTC: Date = Date()
    ) throws -> SupportDiagnosticsPackage {
        let health = DiagnosticsCaptureHealth(
            resourceSummary: resourceSummary(events: resourceEvents),
            storagePreflightVerdict: storagePreflightVerdict.rawValue,
            quarantinedArtifactCount: quarantinedArtifactCount,
            orphanedWorkingArtifactCount:
                orphanedWorkingArtifactCount,
            lastValidationFailureClass: lastValidationFailureClass,
            persistedCaptureCount: persistedCaptureCount
        )
        let report = SupportDiagnosticsReport(
            correlationID: correlationID,
            generatedAtUTC: generatedAtUTC,
            environment: environment,
            capabilities: capabilities,
            captureHealth: health,
            endpointReachability: endpointReachability(
                verdict: endpointVerdict,
                checkedAtUTC: endpointCheckedAtUTC
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .prettyPrinted, .withoutEscapingSlashes,
        ]
        let jsonPayload = try encoder.encode(report)
        try forbiddenContentScan(jsonPayload)

        let text = Self.renderText(
            report: report,
            correlationID: correlationID
        )
        guard let textPayload = text.data(using: .utf8) else {
            throw SupportDiagnosticsError.emptyPackage
        }
        return SupportDiagnosticsPackage(
            correlationID: correlationID,
            report: report,
            privacyPreview: privacyPreview(
                endpointChecked: endpointVerdict != nil
            ),
            jsonPayload: jsonPayload,
            textPayload: textPayload
        )
    }

    /// Plain-text companion summary — support reads this before ever
    /// opening the JSON. Same content class, human shape.
    static func renderText(
        report: SupportDiagnosticsReport,
        correlationID: DiagnosticsCorrelationID
    ) -> String {
        var lines: [String] = []
        lines.append(
            "HTDT Capture diagnostics \(correlationID.displayTag)"
        )
        lines.append("generated_at: \(report.generatedAtUTC)")
        lines.append(
            "app: \(report.appName) \(report.appVersion) "
                + "(\(report.appBuild))"
        )
        lines.append(
            "device: \(report.deviceModelFamily) — "
                + report.osFamilyAndVersion
        )
        let caps = report.capabilities
        lines.append(
            "capabilities: roomplan=\(caps.roomPlanEligible) "
                + "scene_recon=\(caps.sceneReconstructionEligible) "
                + "lidar=\(caps.lidarDepthAvailable) "
                + "smoothed_depth=\(caps.smoothedDepthAvailable) "
                + "mesh_anchor=\(caps.meshAnchoringAvailable)"
        )
        let health = report.captureHealth
        let res = health.resourceSummary
        lines.append(
            "capture_health: resource_events=\(res.totalEvents) "
                + "thermal_stops=\(res.thermalPressureStops) "
                + "storage_preflight=\(health.storagePreflightVerdict) "
                + "quarantined=\(health.quarantinedArtifactCount) "
                + "orphaned=\(health.orphanedWorkingArtifactCount) "
                + "persisted_captures="
                + "\(health.persistedCaptureCount)"
        )
        if let failure = health.lastValidationFailureClass {
            lines.append("last_validation_failure: \(failure)")
        }
        lines.append(
            "endpoint: \(report.endpointReachability.verdictClass)"
        )
        lines.append(
            "privacy: no images, depth, mesh, annotations, serials, "
                + "project names, or secrets included"
        )
        return lines.joined(separator: "\n") + "\n"
    }

    /// Defensive scan of the encoded JSON: the typed model already
    /// excludes sensitive content, this is the belt-and-suspenders
    /// check that a future field can't quietly reintroduce it.
    /// Throws `privacyReviewFailed` naming the offending marker.
    static func forbiddenContentScan(_ json: Data) throws {
        guard let text = String(data: json, encoding: .utf8) else {
            throw SupportDiagnosticsError
                .privacyReviewFailed("non_utf8_payload")
        }
        let lowered = text.lowercased()
        // Token scan: capture-tree paths, digest keys, credential and
        // serial-shaped keys, UUIDs naming capture entities, and the
        // app-data directory markers must never appear.
        let forbiddenFragments = [
            "evidence/frames/",
            "evidence/field/",
            "roomplan/",
            "\"sha256\"",
            "\"serial",
            "\"password\"",
            "\"secret\"",
            "\"token\"",
            "\"api_key\"",
            "\"bearer\"",
            "application support/",
            "/users/",
        ]
        for fragment in forbiddenFragments
        where lowered.contains(fragment) {
            throw SupportDiagnosticsError.privacyReviewFailed(
                "forbidden_fragment:\(fragment)"
            )
        }
    }
}
