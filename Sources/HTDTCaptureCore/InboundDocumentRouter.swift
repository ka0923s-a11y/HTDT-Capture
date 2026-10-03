import Foundation

/// The document kinds the inbound router can hand to an owning
/// workflow (issue bolph71656-ai/HTDT-Capture#393). The router identifies and gates; the
/// domain importers remain authoritative for schema and content
/// validation.
public enum InboundDocumentKind: String, Sendable, CaseIterable {
    /// `.htdtcapture` — a finalized capture bundle archive.
    case captureBundle = "capture_bundle"
    /// `htdt.capture-mission` envelope or a bare
    /// `htdt.capture-task-plan` — both owned by the mission inbox.
    case captureMission = "capture_mission"
    /// `htdt.equipment.catalog-snapshot` reference document.
    case equipmentCatalog = "equipment_catalog"
    /// `.htdtcapturelibrary` — the Capture Library portability
    /// container (legacy bolph71656-ai/HTDT-Capture#378).
    case captureLibraryPackage = "capture_library_package"
    /// Anything else — identified by extension or inspected schema —
    /// that no owning workflow accepts.
    case unsupported
}

/// Bounded preflight outcome for one inbound document: which kind it
/// is and, for JSON documents, the declared schema id found while
/// sniffing (issue bolph71656-ai/HTDT-Capture#393). Identification never trusts a filename when
/// a typed manifest is inspectable — a `.json` carrying a mission
/// routes by its schema, not by an extension the app controls.
public struct InboundDocumentClassification:
    Sendable,
    Equatable
{
    public let kind: InboundDocumentKind
    /// The `schema` value of an inspected JSON document; nil for the
    /// ZIP containers (`.htdtcapture`, `.htdtcapturelibrary`) whose
    /// internal validation happens in the owning importer.
    public let detectedSchemaID: String?
    /// Why an `unsupported` document was refused, operator-safe.
    public let diagnostic: String?

    public init(
        kind: InboundDocumentKind,
        detectedSchemaID: String? = nil,
        diagnostic: String? = nil
    ) {
        self.kind = kind
        self.detectedSchemaID = detectedSchemaID
        self.diagnostic = diagnostic
    }
}

/// Whether the destination workflow may run now given the capture
/// state (issue bolph71656-ai/HTDT-Capture#393). The router decides; the host owns the
/// operator-facing message.
public enum InboundRoutingAvailability:
    String,
    Sendable,
    Equatable
{
    /// Importable now.
    case allowed
    /// Only while no capture session is active — the owning workflow
    /// would otherwise disturb live coordinate authority.
    case idleOnly = "idle_only"
    /// Storable while a capture is active ("saved for later") — the
    /// document is durable and never replaces the active workflow's
    /// inputs; explicit adoption happens from its owning surface.
    case storableDuringActiveCapture =
        "storable_during_active_capture"
    /// No workflow accepts this document.
    case unsupported
}

/// Centralized security-scoped access lifetime (issue bolph71656-ai/HTDT-Capture#393):
/// `begin` synchronously while the open/pick grant is live, hold
/// through the async work, then `finish` exactly once.
public struct SecurityScopedAccess: Sendable {
    public let url: URL
    public let granted: Bool

    public init(url: URL) {
        self.url = url
        self.granted = url.startAccessingSecurityScopedResource()
    }

    public func finish() {
        if granted {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

/// The single validated file-entry boundary for external documents
/// (issue bolph71656-ai/HTDT-Capture#393): identify the document kind by extension for the
/// typed containers and by bounded schema inspection for JSON, then
/// let the owning importer do authoritative content validation.
public enum InboundDocumentRouter {
    /// Extensions the app itself emits/consumes — the stable
    /// user-facing artifacts (legacy bolph71656-ai/HTDT-Capture#393: public UTTypes only for these).
    private static let containerExtensions: [
        String: InboundDocumentKind
    ] = [
        "htdtcapture": .captureBundle,
        "htdtcapturelibrary": .captureLibraryPackage,
    ]

    /// Declared `schema` values routed to their owning workflow.
    private static let knownSchemaIDs: [String: InboundDocumentKind] =
    [
        "htdt.capture-mission": .captureMission,
        "htdt.capture-task-plan": .captureMission,
        "htdt.equipment.catalog-snapshot": .equipmentCatalog,
    ]

    /// Bound on the bytes the classifier will read of a JSON
    /// document; the containers are identified by extension and need
    /// no preflight read.
    private static let sniffByteLimit = 8 * 1024 * 1024

    /// `{schema}`-only envelope — enough to route without trusting
    /// the importer's full contract.
    private struct SchemaEnvelope: Decodable {
        let schema: String?
    }

    /// Classifies an inbound file. Never throws: anything it cannot
    /// positively route lands in `.unsupported` with a diagnostic.
    public static func classify(
        url: URL
    ) -> InboundDocumentClassification {
        let ext = url.pathExtension.lowercased()
        if let kind = containerExtensions[ext] {
            return InboundDocumentClassification(
                kind: kind,
                detectedSchemaID: nil
            )
        }
        // `.htdtmission` is the dedicated mission extension; other
        // JSON payloads (Files drops, mail attachments, legacy
        // `.json` missions and catalogs) route by inspected schema.
        if ext == "htdtmission" {
            return InboundDocumentClassification(
                kind: .captureMission,
                detectedSchemaID: nil
            )
        }
        guard let data = boundedHeadData(url: url) else {
            return InboundDocumentClassification(
                kind: .unsupported,
                diagnostic: "document could not be read"
            )
        }
        guard let envelope = try? JSONDecoder().decode(
            SchemaEnvelope.self,
            from: data
        ), let schema = envelope.schema,
            let kind = knownSchemaIDs[schema]
        else {
            return InboundDocumentClassification(
                kind: .unsupported,
                diagnostic:
                    "no supported document kind could be identified"
            )
        }
        return InboundDocumentClassification(
            kind: kind,
            detectedSchemaID: schema
        )
    }

    /// Workflow gating: bundle and library packages import only while
    /// idle; missions and catalogs may be stored during an active
    /// capture and adopted explicitly later (legacy bolph71656-ai/HTDT-Capture#393).
    public static func availability(
        kind: InboundDocumentKind,
        captureState: CaptureState
    ) -> InboundRoutingAvailability {
        switch kind {
        case .captureBundle, .captureLibraryPackage:
            return captureState == .idle ? .allowed : .idleOnly
        case .captureMission, .equipmentCatalog:
            return .storableDuringActiveCapture
        case .unsupported:
            return .unsupported
        }
    }

    private static func boundedHeadData(url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }
        guard let size = try? handle.seekToEnd(),
              size <= UInt64(sniffByteLimit)
        else {
            return nil
        }
        try? handle.seek(toOffset: 0)
        return try? handle.read(upToCount: sniffByteLimit)
    }
}
