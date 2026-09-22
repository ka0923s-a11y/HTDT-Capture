import Foundation

/// Errors raised by the paired Mission receive leg (issue #422).
/// Every failure fails closed: a mission whose bytes cannot be
/// verified is never imported, and a receipt is only ever recorded
/// for what actually happened.
public enum HTDTMissionReceiveError: Error, Sendable, Equatable {
    /// The destination is not a paired, unrevoked receiver with a
    /// Mission endpoint — the receive leg never runs against
    /// unpaired or revoked peers (#422 §privacy/revocation).
    case pairingRequired
    /// The paired receiver advertises no Mission-serving endpoint —
    /// the manual Files/share-sheet import path remains the
    /// fallback (#422 §offline).
    case missionsNotServed
    case invalidEndpointURL
    case transportFailed(String)
    case endpointRejected(statusCode: Int)
    /// The listing/receipt document was undecodable or lied about
    /// its schema.
    case malformedDocument
    /// The descriptor or payload exceeded its bounded read size.
    case documentTooLarge
    /// Downloaded bytes did not match the descriptor's pinned
    /// digest/size — the mission is refused, never repaired in
    /// place (#422: a mission is pinned to its issue-time baseline).
    case integrityMismatch
}

/// This device's stable Capture identity, presented to paired
/// receivers so Mission enumeration is scoped to this pairing
/// (issue #422: "pending Missions for this paired Capture identity").
/// Created once and reused across every retry — a retry never mints
/// a new identity.
public struct HTDTCaptureIdentity: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.capture-identity"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    /// UUIDv4 generated once at first use and persisted.
    public let captureInstanceID: String
    public let createdAtUTC: String

    public init(
        captureInstanceID: String,
        createdAtUTC: String
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureInstanceID = captureInstanceID
        self.createdAtUTC = createdAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureInstanceID = "capture_instance_id"
        case createdAtUTC = "created_at"
    }
}

/// Persisted at `<captureRoot>/capture-identity.json` — the stable
/// identity the receive leg and (future) pairing-scoped protocols
/// present to paired receivers.
public struct HTDTCaptureIdentityStore: Sendable {
    public let fileURL: URL

    public init(captureRoot: URL) {
        self.fileURL = captureRoot.appendingPathComponent(
            "capture-identity.json",
            isDirectory: false
        )
    }

    /// Loads the identity, minting and persisting it on first use.
    /// Retries never mint a second identity (#422 §offline).
    public func loadOrCreate(
        nowUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws -> HTDTCaptureIdentity {
        if let data = try? Data(contentsOf: fileURL),
           let identity = try? JSONDecoder().decode(
               HTDTCaptureIdentity.self,
               from: data
           ),
           identity.schema == HTDTCaptureIdentity.schema {
            return identity
        }
        let identity = HTDTCaptureIdentity(
            captureInstanceID: UUID().uuidString.lowercased(),
            createdAtUTC: nowUTC
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(identity)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary)
        _ = try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: temporary, to: fileURL)
        return identity
    }
}

/// Metadata-only descriptor of one Mission package a paired
/// receiver offers this Capture identity (issue #422 §enumeration).
/// Deliberately carries labels, sizes and digests only — never
/// arbitrary project contents; the exact bytes only move on an
/// explicit download keyed by `packageID`.
public struct HTDTPendingMissionDescriptor:
    Codable, Sendable, Equatable, Identifiable
{
    /// Issuer-assigned package identity (the artifact id).
    public let packageID: String
    /// Mission id inside the package, when the issuer declares it.
    public let missionID: String?
    public let purpose: String?
    /// Routing refs (#607 compatibility): the project the mission
    /// belongs to and the room it names — never a substitute for
    /// receiver identity.
    public let projectRef: String?
    public let roomLabel: String?
    /// Issued/supersession state for operator display.
    public let issuedAtUTC: String?
    public let supersedesPackageID: String?
    /// Exact payload byte size and `sha256:<hex>` digest the
    /// download must match before import.
    public let byteSize: Int64
    public let packageSHA256: String
    /// `htdt.capture-mission` schema version the package requires.
    public let requiredSchemaVersion: String?
    /// Minimum receiver-requirement summary the mission carries
    /// forward for preflight (#374), when the issuer relays it.
    public let receiverRequirement: HTDTMissionReceiverRequirement?

    public init(
        packageID: String,
        missionID: String? = nil,
        purpose: String? = nil,
        projectRef: String? = nil,
        roomLabel: String? = nil,
        issuedAtUTC: String? = nil,
        supersedesPackageID: String? = nil,
        byteSize: Int64,
        packageSHA256: String,
        requiredSchemaVersion: String? = nil,
        receiverRequirement: HTDTMissionReceiverRequirement? = nil
    ) {
        self.packageID = packageID
        self.missionID = missionID
        self.purpose = purpose
        self.projectRef = projectRef
        self.roomLabel = roomLabel
        self.issuedAtUTC = issuedAtUTC
        self.supersedesPackageID = supersedesPackageID
        self.byteSize = byteSize
        self.packageSHA256 = packageSHA256
        self.requiredSchemaVersion = requiredSchemaVersion
        self.receiverRequirement = receiverRequirement
    }

    public var id: String { packageID }

    private enum CodingKeys: String, CodingKey {
        case packageID = "package_id"
        case missionID = "mission_id"
        case purpose
        case projectRef = "project_ref"
        case roomLabel = "room_label"
        case issuedAtUTC = "issued_at"
        case supersedesPackageID = "supersedes_package_id"
        case byteSize = "byte_size"
        case packageSHA256 = "package_sha256"
        case requiredSchemaVersion = "required_schema_version"
        case receiverRequirement = "receiver_requirement"
    }
}

/// The receiver's pending-Mission listing document
/// (`htdt.mission-listing`) — bounded, pairing-scoped, metadata only.
public struct HTDTPendingMissionListing:
    Codable, Sendable, Equatable
{
    public static let schema = "htdt.mission-listing"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    /// The Capture identity the listing is scoped to — echoed back
    /// so a mismatched listing is detected rather than trusted.
    public let captureInstanceID: String?
    public let packages: [HTDTPendingMissionDescriptor]

    public init(
        captureInstanceID: String? = nil,
        packages: [HTDTPendingMissionDescriptor] = []
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureInstanceID = captureInstanceID
        self.packages = packages
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureInstanceID = "capture_instance_id"
        case packages
    }
}

/// What the receive leg reports back to the issuing receiver — and
/// records locally — for one fetched package (issue #422 §receipt).
/// "received" means *received and staged in the Mission Inbox*;
/// it never claims the mission was started, completed or delivered.
public struct HTDTMissionReceiveReceipt:
    Codable, Sendable, Equatable, Identifiable
{
    public static let schema = "htdt.capture.mission-receipt"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let receiptID: String
    /// Package identity and exact payload digest received.
    public let packageID: String
    public let packageSHA256: String
    /// The Capture identity that pulled the package.
    public let captureInstanceID: String
    /// The paired receiver the package came from.
    public let pairedDestinationID: String
    public let receiverInstanceID: String
    /// Mission Inbox record the bytes landed under, when the import
    /// succeeded (duplicate/superseding imports report the existing
    /// or new record id).
    public let missionRecordID: String?
    public let receivedAtUTC: String
    /// Canonical importer's verdict: `imported`, `duplicate`,
    /// `superseding`, `conflicting_identity`, `unsupported_schema`,
    /// `invalid_payload`, or `integrity_mismatch`.
    public let validationResult: String
    public let detail: String?

    public init(
        receiptID: String,
        packageID: String,
        packageSHA256: String,
        captureInstanceID: String,
        pairedDestinationID: String,
        receiverInstanceID: String,
        missionRecordID: String? = nil,
        receivedAtUTC: String,
        validationResult: String,
        detail: String? = nil
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.receiptID = receiptID
        self.packageID = packageID
        self.packageSHA256 = packageSHA256
        self.captureInstanceID = captureInstanceID
        self.pairedDestinationID = pairedDestinationID
        self.receiverInstanceID = receiverInstanceID
        self.missionRecordID = missionRecordID
        self.receivedAtUTC = receivedAtUTC
        self.validationResult = validationResult
        self.detail = detail
    }

    public var id: String { receiptID }

    /// True when the receiver may mark its queue entry `received`.
    public var receiverMayMarkReceived: Bool {
        validationResult == "imported"
            || validationResult == "duplicate"
            || validationResult == "superseding"
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case receiptID = "receipt_id"
        case packageID = "package_id"
        case packageSHA256 = "package_sha256"
        case captureInstanceID = "capture_instance_id"
        case pairedDestinationID = "paired_destination_id"
        case receiverInstanceID = "receiver_instance_id"
        case missionRecordID = "mission_record_id"
        case receivedAtUTC = "received_at"
        case validationResult = "validation_result"
        case detail
    }
}

/// Append-only ledger of receive receipts at
/// `<captureRoot>/mission-receive-receipts.json` — provenance kept
/// even after a pairing is revoked (#422 §revocation).
public struct HTDTMissionReceiveReceiptStore: Sendable {
    public struct Document: Codable, Sendable, Equatable {
        public static let schema =
            "htdt.capture.mission-receive-receipts"
        public static let schemaVersion = "1.0.0"

        public let schema: String
        public let schemaVersion: String
        public var receipts: [HTDTMissionReceiveReceipt]

        public init(receipts: [HTDTMissionReceiveReceipt] = []) {
            self.schema = Self.schema
            self.schemaVersion = Self.schemaVersion
            self.receipts = receipts
        }

        private enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case receipts
        }
    }

    public let fileURL: URL

    public init(captureRoot: URL) {
        self.fileURL = captureRoot.appendingPathComponent(
            "mission-receive-receipts.json",
            isDirectory: false
        )
    }

    public func load() throws -> Document {
        guard FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return Document()
        }
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(
                  Document.self, from: data
              ),
              document.schema == Document.schema,
              document.schemaVersion == Document.schemaVersion
        else {
            throw HTDTMissionReceiveError.malformedDocument
        }
        return document
    }

    public func append(_ receipt: HTDTMissionReceiveReceipt) throws {
        var document = try load()
        document.receipts.append(receipt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary)
        _ = try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: temporary, to: fileURL)
    }

    public func receipts(
        for pairedDestinationID: String
    ) throws -> [HTDTMissionReceiveReceipt] {
        try load().receipts.filter {
            $0.pairedDestinationID == pairedDestinationID
        }
    }
}

/// Transport seam for the receive leg (issue #422): the real client
/// runs HTTPS under the paired receiver's TLS pin; tests substitute
/// scripted fixtures. One artifact, one validator — this seam only
/// moves bytes; `HTDTMissionInboxStore.importMission` remains the
/// canonical inbound path.
public protocol HTDTMissionReceiveTransport: Sendable {
    /// Lists pending Mission packages offered to this Capture
    /// identity — pairing-scoped, metadata only.
    func listPending(
        captureInstanceID: String,
        endpoint: URL,
        pinnedIdentity: String?
    ) async throws -> HTDTPendingMissionListing

    /// Downloads the exact bytes of one offered package, bounded by
    /// `maxBytes`; the caller verifies the pinned digest before any
    /// import is attempted.
    func downloadPackage(
        packageID: String,
        captureInstanceID: String,
        endpoint: URL,
        pinnedIdentity: String?,
        maxBytes: Int64
    ) async throws -> Data

    /// Posts a receive receipt back to the receiver so its queue
    /// advances pending → received / failed (#422 §receipt).
    func postReceipt(
        _ receipt: HTDTMissionReceiveReceipt,
        endpoint: URL,
        pinnedIdentity: String?
    ) async throws
}

/// URL endpoints of a paired receiver's Mission-serving service.
/// Derived from `missionsEndpointURL` recorded at pairing time —
/// the receive leg never invents paths against the upload endpoint.
public struct HTDTMissionServiceEndpoints: Sendable, Equatable {
    public let listing: URL
    public let packageBase: URL

    public init?(missionsEndpointURL: String) {
        guard let base = URL(string: missionsEndpointURL),
              base.scheme?.lowercased() == "https",
              base.host != nil
        else {
            return nil
        }
        self.listing = base
        self.packageBase = base
    }

    public func packageURL(packageID: String) -> URL? {
        packageBase.appendingPathComponent(packageID)
    }

    public func receiptURL(packageID: String) -> URL? {
        packageBase.appendingPathComponent(packageID)
            .appendingPathComponent("receipt")
    }
}

/// Real HTTPS transport for the receive leg (issue #422). All calls
/// run under `HTDTIdentityPinningSession` when the destination is
/// paired — the pin replaces CA trust only for this receiver's
/// exact certificate, same contract as the upload path.
public struct HTDTMissionReceiveClient: HTDTMissionReceiveTransport {
    /// Listings are small metadata documents — anything larger is
    /// refused rather than parsed (#422 bounded enumeration).
    public static let maxListingBytes: Int64 = 256 * 1024
    /// A Mission package is an envelope JSON, not a bulk artifact;
    /// descriptors claiming more are refused before download.
    public static let maxPackageBytes: Int64 = 16 * 1024 * 1024

    public init() {}

    public func listPending(
        captureInstanceID: String,
        endpoint: URL,
        pinnedIdentity: String? = nil
    ) async throws -> HTDTPendingMissionListing {
        var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(
                name: "capture_instance_id",
                value: captureInstanceID
            )
        ]
        guard let url = components?.url else {
            throw HTDTMissionReceiveError.invalidEndpointURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            captureInstanceID,
            forHTTPHeaderField: "X-HTDT-Capture-Instance-ID"
        )
        let data = try await perform(
            request, pinnedIdentity: pinnedIdentity,
            maxBytes: Self.maxListingBytes
        )
        guard let listing = try? JSONDecoder().decode(
            HTDTPendingMissionListing.self, from: data
        ), listing.schema == HTDTPendingMissionListing.schema
        else {
            throw HTDTMissionReceiveError.malformedDocument
        }
        // A listing echoed for another capture identity is never
        // trusted — enumeration is strictly pairing-scoped.
        if let echoed = listing.captureInstanceID,
           echoed != captureInstanceID
        {
            throw HTDTMissionReceiveError.malformedDocument
        }
        return listing
    }

    public func downloadPackage(
        packageID: String,
        captureInstanceID: String,
        endpoint: URL,
        pinnedIdentity: String? = nil,
        maxBytes: Int64 = Int64(maxPackageBytes)
    ) async throws -> Data {
        guard let base = URLComponents(
            url: endpoint, resolvingAgainstBaseURL: false
        )?.url else {
            throw HTDTMissionReceiveError.invalidEndpointURL
        }
        var request = URLRequest(
            url: base.appendingPathComponent(packageID)
        )
        request.httpMethod = "GET"
        request.setValue(
            captureInstanceID,
            forHTTPHeaderField: "X-HTDT-Capture-Instance-ID"
        )
        return try await perform(
            request, pinnedIdentity: pinnedIdentity,
            maxBytes: maxBytes
        )
    }

    public func postReceipt(
        _ receipt: HTDTMissionReceiveReceipt,
        endpoint: URL,
        pinnedIdentity: String? = nil
    ) async throws {
        guard let base = URLComponents(
            url: endpoint, resolvingAgainstBaseURL: false
        )?.url else {
            throw HTDTMissionReceiveError.invalidEndpointURL
        }
        var request = URLRequest(
            url: base.appendingPathComponent(receipt.packageID)
                .appendingPathComponent("receipt")
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            receipt.captureInstanceID,
            forHTTPHeaderField: "X-HTDT-Capture-Instance-ID"
        )
        request.httpBody = try JSONEncoder().encode(receipt)
        _ = try await perform(
            request, pinnedIdentity: pinnedIdentity,
            maxBytes: Self.maxListingBytes
        )
    }

    private func perform(
        _ request: URLRequest,
        pinnedIdentity: String?,
        maxBytes: Int64
    ) async throws -> Data {
        let transport = pinnedIdentity.map {
            HTDTIdentityPinningSession.session(pinnedIdentity: $0)
        } ?? URLSession.shared
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw HTDTMissionReceiveError.transportFailed(
                String(describing: error)
            )
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTDTMissionReceiveError.malformedDocument
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTDTMissionReceiveError.endpointRejected(
                statusCode: http.statusCode
            )
        }
        guard Int64(data.count) <= maxBytes else {
            throw HTDTMissionReceiveError.documentTooLarge
        }
        return data
    }
}

/// Outcome of one receive sync against one paired destination.
public struct HTDTMissionReceiveReport: Sendable, Equatable {
    public let pairedDestinationID: String
    public let receiverName: String
    public let attemptedAtUTC: String
    /// Descriptors the receiver offered this identity.
    public var enumerated: Int
    /// Packages newly imported into the Mission Inbox.
    public var imported: Int
    /// Byte-identical packages already staged — idempotent no-ops
    /// (the receipt still posts so the receiver marks `received`).
    public var duplicates: Int
    /// Packages that landed as superseding records.
    public var superseded: Int
    /// Packages refused: same mission identity with different bytes
    /// and no declared supersession — a hard conflict, never a
    /// silent merge (#422 §multiple receivers).
    public var conflicts: [String]
    /// Packages refused on integrity/validation grounds.
    public var rejected: [String]
    /// Non-fatal notes (receiver doesn't serve Missions, receipt
    /// post failed, destination revoked).
    public var notes: [String]

    public init(
        pairedDestinationID: String,
        receiverName: String,
        attemptedAtUTC: String
    ) {
        self.pairedDestinationID = pairedDestinationID
        self.receiverName = receiverName
        self.attemptedAtUTC = attemptedAtUTC
        self.enumerated = 0
        self.imported = 0
        self.duplicates = 0
        self.superseded = 0
        self.conflicts = []
        self.rejected = []
        self.notes = []
    }
}

/// The Capture-initiated Mission receive service (issue #422).
/// No inbound listener: the app pulls pending missions from each
/// paired receiver while foregrounded, verifies every byte against
/// the descriptor's pinned digest, and feeds the canonical Mission
/// Inbox importer — the same validator used by Files/share-sheet
/// imports, so there is exactly one Mission model in memory.
public struct HTDTMissionReceiveService: Sendable {
    public let captureRoot: URL
    public let transport: any HTDTMissionReceiveTransport
    public let identityStore: HTDTCaptureIdentityStore
    public let destinationStore: PairedHTDTDestinationStore
    public let inboxStore: HTDTMissionInboxStore
    public let receiptStore: HTDTMissionReceiveReceiptStore

    public init(
        captureRoot: URL,
        transport: any HTDTMissionReceiveTransport
            = HTDTMissionReceiveClient()
    ) {
        self.captureRoot = captureRoot
        self.transport = transport
        self.identityStore = HTDTCaptureIdentityStore(
            captureRoot: captureRoot
        )
        self.destinationStore = PairedHTDTDestinationStore(
            captureRoot: captureRoot
        )
        self.inboxStore = HTDTMissionInboxStore(captureRoot: captureRoot)
        self.receiptStore = HTDTMissionReceiveReceiptStore(
            captureRoot: captureRoot
        )
    }

    /// Pull pending missions from every active pairing (#422 §UX:
    /// invoked by "Check HTDT", inbox open, app-active, and
    /// post-pairing refresh — a bounded foreground action, never a
    /// polling loop). Revoked destinations are skipped; their
    /// receipts and records persist.
    @discardableResult
    public func syncAll(
        nowUTC: String = BundleTimestamp.utcString(from: Date())
    ) async -> [HTDTMissionReceiveReport] {
        let destinations =
            (try? destinationStore.activeDestinations()) ?? []
        var reports: [HTDTMissionReceiveReport] = []
        for destination in destinations {
            let report = await sync(
                destination: destination, nowUTC: nowUTC
            )
            reports.append(report)
        }
        return reports
    }

    /// Pull pending missions from one paired destination.
    @discardableResult
    public func sync(
        destination: PairedHTDTDestination,
        nowUTC: String = BundleTimestamp.utcString(from: Date())
    ) async -> HTDTMissionReceiveReport {
        var report = HTDTMissionReceiveReport(
            pairedDestinationID: destination.destinationID,
            receiverName: destination.displayName,
            attemptedAtUTC: nowUTC
        )
        guard !destination.revoked else {
            // Revocation stops fetching but keeps local records and
            // provenance (#422 §revocation).
            report.notes.append("destination_revoked")
            return report
        }
        guard let endpoints = HTDTMissionServiceEndpoints(
            missionsEndpointURL: destination.missionsEndpointURL ?? ""
        ) else {
            report.notes.append("missions_not_served")
            return report
        }
        // A cached capability document that explicitly withholds
        // Mission serving short-circuits the pull (#422 §capability
        // handshake); an absent cache means "unknown", not refused.
        if destination.cachedCapability != nil,
           destination.cachedCapability?.document
               .missionPackagesServed == false
        {
            report.notes.append("missions_not_served")
            return report
        }

        let identity: HTDTCaptureIdentity
        do {
            identity = try identityStore.loadOrCreate(nowUTC: nowUTC)
        } catch {
            report.notes.append("identity_unavailable")
            return report
        }

        let listing: HTDTPendingMissionListing
        do {
            listing = try await transport.listPending(
                captureInstanceID: identity.captureInstanceID,
                endpoint: endpoints.listing,
                pinnedIdentity: destination.pinnedIdentity
            )
            try? destinationStore.markSeen(
                destinationID: destination.destinationID,
                atUTC: nowUTC
            )
        } catch {
            // Offline or unreachable: pending missions stay pending
            // and retry cleanly later (#422 §offline).
            report.notes.append(
                "listing_failed:" + String(describing: error)
            )
            return report
        }
        report.enumerated = listing.packages.count

        for descriptor in listing.packages {
            await receive(
                descriptor: descriptor,
                destination: destination,
                endpoints: endpoints,
                captureInstanceID: identity.captureInstanceID,
                report: &report,
                nowUTC: nowUTC
            )
        }
        return report
    }

    private func receive(
        descriptor: HTDTPendingMissionDescriptor,
        destination: PairedHTDTDestination,
        endpoints: HTDTMissionServiceEndpoints,
        captureInstanceID: String,
        report: inout HTDTMissionReceiveReport,
        nowUTC: String
    ) async {
        func recordReceipt(
            _ validation: String,
            recordID: String?,
            detail: String?
        ) async {
            let receipt = HTDTMissionReceiveReceipt(
                receiptID: UUID().uuidString.lowercased(),
                packageID: descriptor.packageID,
                packageSHA256: descriptor.packageSHA256,
                captureInstanceID: captureInstanceID,
                pairedDestinationID: destination.destinationID,
                receiverInstanceID: destination.receiverInstanceID,
                missionRecordID: recordID,
                receivedAtUTC: nowUTC,
                validationResult: validation,
                detail: detail
            )
            try? receiptStore.append(receipt)
            // Best-effort acknowledgment — a receipt post failure
            // never rolls back a staged import; the next sync's
            // duplicate retry re-acknowledges (#422 §offline).
            if receipt.receiverMayMarkReceived,
               let receiptURL = endpoints.receiptURL(
                   packageID: descriptor.packageID
               )
            {
                _ = receiptURL
                do {
                    try await transport.postReceipt(
                        receipt,
                        endpoint: endpoints.packageBase,
                        pinnedIdentity: destination.pinnedIdentity
                    )
                } catch {
                    report.notes.append(
                        "receipt_post_failed:" + descriptor.packageID
                    )
                }
            }
        }

        // Idempotency: an already-imported mission with the same
        // pinned digest is acknowledged again without a download —
        // duplicate imports are a no-op (#422 §inbox semantics).
        if let missionID = descriptor.missionID,
           let existing = try? inboxStore.record(
               missionID: missionID
           ),
           existing.payloadSHA256
               == HTDTPinnedIdentity.digestText(
                   descriptor.packageSHA256
               )
        {
            report.duplicates += 1
            await recordReceipt("duplicate", recordID: existing.recordID,
                         detail: nil)
            return
        }

        guard descriptor.byteSize
                <= Int64(HTDTMissionReceiveClient.maxPackageBytes),
              descriptor.byteSize > 0,
              HTDTPinnedIdentity.digestText(
                  descriptor.packageSHA256
              ) != nil
        else {
            report.rejected.append(descriptor.packageID)
            await recordReceipt(
                "integrity_mismatch", recordID: nil,
                detail: "descriptor out of bounds"
            )
            return
        }

        let data: Data
        do {
            data = try await transport.downloadPackage(
                packageID: descriptor.packageID,
                captureInstanceID: captureInstanceID,
                endpoint: endpoints.packageBase,
                pinnedIdentity: destination.pinnedIdentity,
                maxBytes: descriptor.byteSize
            )
        } catch {
            report.notes.append(
                "download_failed:" + descriptor.packageID
            )
            return
        }
        // Verify the exact bytes: digest + size must match the
        // descriptor before the importer ever sees them — a mission
        // is pinned to its issue-time baseline and never patched
        // on the way in (#422 §mission immutability).
        guard data.count == descriptor.byteSize,
              EvidenceIntegrity.sha256(of: data).value
                  == HTDTPinnedIdentity.digestText(
                      descriptor.packageSHA256
                  )
        else {
            report.rejected.append(descriptor.packageID)
            await recordReceipt(
                "integrity_mismatch", recordID: nil,
                detail: "downloaded bytes differ from descriptor"
            )
            return
        }

        do {
            let outcome = try inboxStore.importMission(data: data)
            switch outcome {
            case .imported(let record):
                report.imported += 1
                await recordReceipt("imported", recordID: record.recordID,
                             detail: nil)
            case .duplicate(let record):
                report.duplicates += 1
                await recordReceipt("duplicate", recordID: record.recordID,
                             detail: nil)
            case .superseding(let record, let superseded):
                report.superseded += 1
                await recordReceipt(
                    "superseding", recordID: record.recordID,
                    detail: "supersedes " + superseded.missionID
                )
            }
        } catch let error as HTDTMissionInboxError {
            switch error {
            case .conflictingIdentity:
                // Same mission id, different bytes, no declared
                // supersession — a hard conflict surfaced to the
                // operator, never silently merged (#422).
                report.conflicts.append(descriptor.packageID)
                await recordReceipt(
                    "conflicting_identity", recordID: nil,
                    detail: descriptor.missionID
                )
            case .unsupportedSchema:
                report.rejected.append(descriptor.packageID)
                await recordReceipt(
                    "unsupported_schema", recordID: nil,
                    detail: descriptor.requiredSchemaVersion
                )
            default:
                report.rejected.append(descriptor.packageID)
                await recordReceipt(
                    "invalid_payload", recordID: nil,
                    detail: String(describing: error)
                )
            }
        } catch {
            report.rejected.append(descriptor.packageID)
            await recordReceipt(
                "invalid_payload", recordID: nil,
                detail: String(describing: error)
            )
        }
    }
}
