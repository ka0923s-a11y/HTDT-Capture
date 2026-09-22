import Foundation

/// Errors raised by the destination pairing flow (issue #379).
public enum HTDTPairingError: Error, Sendable, Equatable {
    /// The scanned/provided payload is not a `htdt.receiver-pairing`
    /// document this app version can accept.
    case invalidPairingPayload(String)
    /// The payload's endpoint is not an https URL — pairing never
    /// downgrades a destination to plain HTTP.
    case nonSecureEndpoint
    /// The pinned identity is not a canonical `sha256:<64hex>` digest.
    case invalidPinnedIdentity
    /// The pairing token's validity window has passed.
    case pairingPayloadExpired
    /// No paired destination exists under that identifier.
    case unknownDestination(String)
    /// The persisted store document is missing required invariants.
    case unreadableDocument
}

/// Canonical `sha256:<64 lowercase hex>` identity pin recorded during
/// the #379 pairing ceremony. The digest covers the receiver's leaf
/// TLS certificate (DER bytes) so a paired destination keeps working
/// with a receiver-managed self-signed certificate without disabling
/// TLS verification globally.
public struct HTDTPinnedIdentity: Codable, Sendable, Equatable {
    public let text: String

    public init(_ text: String) throws {
        guard Self.digestText(text) != nil else {
            throw HTDTPairingError.invalidPinnedIdentity
        }
        self.text = text
    }

    /// Extracts the lowercase hex digest from a pin string of the form
    /// `sha256:<64hex>`; returns nil for anything else.
    public static func digestText(_ text: String) -> String? {
        guard text.lowercased().hasPrefix("sha256:") else {
            return nil
        }
        let hex = String(text.dropFirst("sha256:".count))
        guard hex.count == 64,
              hex.allSatisfy({ $0.isHexDigit }),
              hex == hex.lowercased()
        else {
            return nil
        }
        return hex
    }
}

/// QR-carried payload a local HTDT receiver broadcasts for pairing
/// (issue #379). The pairing token plus the pinned identity let the
/// app show a short verification code the operator confirms on the
/// receiver's own display before the destination is trusted.
public struct HTDTReceiverPairingPayload: Codable, Sendable, Equatable {
    public static let schema = "htdt.receiver-pairing"
    public static let supportedSchemaVersions = ["1.0.0"]

    public let schema: String
    public let schemaVersion: String
    /// Stable identity of the receiver instance across re-pairing.
    public let receiverInstanceID: String
    public let displayName: String
    /// HTTPS endpoint that accepts `POST` of `.htdtcapture` bytes.
    public let endpointURL: String
    /// Optional endpoint serving the `htdt.endpoint-capabilities`
    /// document (#374).
    public let capabilityEndpointURL: String?
    /// `sha256:<64hex>` of the receiver's leaf TLS certificate.
    public let pinnedIdentity: String
    /// One-time ceremony token mixed into the verification code.
    public let pairingToken: String
    /// Optional project the receiver declares itself bound to.
    public let projectRef: String?
    /// Optional UTC expiry after which the payload must not be used.
    public let expiresAtUTC: String?

    public init(
        receiverInstanceID: String,
        displayName: String,
        endpointURL: String,
        capabilityEndpointURL: String? = nil,
        pinnedIdentity: String,
        pairingToken: String,
        projectRef: String? = nil,
        expiresAtUTC: String? = nil
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.supportedSchemaVersions[0]
        self.receiverInstanceID = receiverInstanceID
        self.displayName = displayName
        self.endpointURL = endpointURL
        self.capabilityEndpointURL = capabilityEndpointURL
        self.pinnedIdentity = pinnedIdentity
        self.pairingToken = pairingToken
        self.projectRef = projectRef
        self.expiresAtUTC = expiresAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case receiverInstanceID = "receiver_instance_id"
        case displayName = "display_name"
        case endpointURL = "endpoint_url"
        case capabilityEndpointURL = "capability_endpoint_url"
        case pinnedIdentity = "pinned_identity"
        case pairingToken = "pairing_token"
        case projectRef = "project_ref"
        case expiresAtUTC = "expires_at"
    }

    /// Decodes and validates a QR payload. Fails closed: unsupported
    /// schema versions, non-https endpoints, malformed pins and
    /// expired tokens are all rejected rather than partially paired.
    public init(data: Data) throws {
        guard let payload = try? JSONDecoder().decode(
            HTDTReceiverPairingPayload.self,
            from: data
        ) else {
            throw HTDTPairingError.invalidPairingPayload("undecodable")
        }
        guard payload.schema == Self.schema,
              Self.supportedSchemaVersions.contains(
                payload.schemaVersion
              )
        else {
            throw HTDTPairingError.invalidPairingPayload(
                "unsupported_schema"
            )
        }
        guard !payload.receiverInstanceID.isEmpty,
              !payload.displayName.isEmpty,
              !payload.pairingToken.isEmpty
        else {
            throw HTDTPairingError.invalidPairingPayload(
                "missing_identity"
            )
        }
        guard let endpoint = URL(string: payload.endpointURL),
              endpoint.scheme?.lowercased() == "https",
              endpoint.host != nil
        else {
            throw HTDTPairingError.nonSecureEndpoint
        }
        if let capability = payload.capabilityEndpointURL {
            guard let capabilityURL = URL(string: capability),
                  capabilityURL.scheme?.lowercased() == "https",
                  capabilityURL.host != nil
            else {
                throw HTDTPairingError.nonSecureEndpoint
            }
        }
        guard HTDTPinnedIdentity.digestText(payload.pinnedIdentity)
                != nil
        else {
            throw HTDTPairingError.invalidPinnedIdentity
        }
        if let expiry = payload.expiresAtUTC {
            guard SchemaTimestampText.isUTCTimestamp(expiry),
                  BundleTimestamp.utcString(from: Date()) < expiry
            else {
                throw HTDTPairingError.pairingPayloadExpired
            }
        }
        self = payload
    }

    /// Short code shown on both devices during pairing so the operator
    /// confirms they are pairing with the receiver in front of them —
    /// SHA-256 of `receiver_instance_id | pairing_token | pin`,
    /// presented as two groups of four hex digits.
    public var verificationCode: String {
        let material = receiverInstanceID + "|" + pairingToken + "|"
            + pinnedIdentity
        let hex = EvidenceIntegrity.sha256(
            of: Data(material.utf8)
        ).value
        let prefix = String(hex.prefix(8)).uppercased()
        return prefix.prefix(4) + "-" + prefix.suffix(4)
    }
}

/// A QR-paired, identity-pinned HTDT receiver persisted on this
/// device (issue #379). Appears to the send flow as a named
/// `.endpoint` destination whose pin and provenance are recorded.
public struct PairedHTDTDestination:
    Codable, Sendable, Equatable, Identifiable
{
    /// Device-local identifier for this pairing (UUIDv4).
    public let destinationID: String
    public let displayName: String
    public let receiverInstanceID: String
    public let endpointURL: String
    public let capabilityEndpointURL: String?
    public let pinnedIdentity: String
    public let projectRef: String?
    public let pairedAtUTC: String
    /// Most recent successful contact or capability fetch.
    public let lastSeenAtUTC: String?
    /// Cached capability document and its fetch time — always labeled
    /// with when it was fetched, since a cache is never presented as
    /// live state (issue #374).
    public let cachedCapability: HTDTEndpointCapabilitySnapshot?

    /// `true` while the pairing is trusted; revoking keeps the record
    /// (and its receipts) but removes it from selectable destinations.
    public let revoked: Bool

    public init(
        destinationID: String,
        displayName: String,
        receiverInstanceID: String,
        endpointURL: String,
        capabilityEndpointURL: String? = nil,
        pinnedIdentity: String,
        projectRef: String? = nil,
        pairedAtUTC: String,
        lastSeenAtUTC: String? = nil,
        cachedCapability: HTDTEndpointCapabilitySnapshot? = nil,
        revoked: Bool = false
    ) {
        self.destinationID = destinationID
        self.displayName = displayName
        self.receiverInstanceID = receiverInstanceID
        self.endpointURL = endpointURL
        self.capabilityEndpointURL = capabilityEndpointURL
        self.pinnedIdentity = pinnedIdentity
        self.projectRef = projectRef
        self.pairedAtUTC = pairedAtUTC
        self.lastSeenAtUTC = lastSeenAtUTC
        self.cachedCapability = cachedCapability
        self.revoked = revoked
    }

    public var id: String { destinationID }

    private enum CodingKeys: String, CodingKey {
        case destinationID = "destination_id"
        case displayName = "display_name"
        case receiverInstanceID = "receiver_instance_id"
        case endpointURL = "endpoint_url"
        case capabilityEndpointURL = "capability_endpoint_url"
        case pinnedIdentity = "pinned_identity"
        case projectRef = "project_ref"
        case pairedAtUTC = "paired_at"
        case lastSeenAtUTC = "last_seen_at"
        case cachedCapability = "cached_capability"
        case revoked
    }

    /// The destination as the send flow sees it — a named endpoint.
    public var handoffDestination: HTDTHandoffDestination {
        HTDTHandoffDestination(
            name: displayName,
            kind: .endpoint,
            url: endpointURL
        )
    }
}

/// Store for QR-paired destinations (issue #379):
/// `<captureRoot>/paired-destinations.json`. Re-pairing a receiver
/// instance replaces its record (new pin, endpoint and pairing time);
/// forgetting deletes it outright; revoking keeps the history but
/// hides the destination. Pin and receipts are never rewritten.
public struct PairedHTDTDestinationStore: Sendable {
    public struct Document: Codable, Sendable, Equatable {
        public static let schema = "htdt.capture.paired-destinations"
        public static let schemaVersion = "1.0.0"

        public let schema: String
        public let schemaVersion: String
        public var destinations: [PairedHTDTDestination]

        public init(destinations: [PairedHTDTDestination] = []) {
            self.schema = Self.schema
            self.schemaVersion = Self.schemaVersion
            self.destinations = destinations
        }

        private enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case destinations
        }
    }

    public let fileURL: URL

    public init(captureRoot: URL) {
        self.fileURL = captureRoot.appendingPathComponent(
            "paired-destinations.json",
            isDirectory: false
        )
    }

    public func load() throws -> Document {
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            return Document()
        }
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(
                Document.self,
                from: data
              ),
              document.schema == Document.schema,
              document.schemaVersion == Document.schemaVersion
        else {
            throw HTDTPairingError.unreadableDocument
        }
        return document
    }

    /// Records a confirmed pairing. If a pairing already exists for
    /// the same receiver instance, re-pairing replaces it wholesale —
    /// the operator just confirmed a fresh QR ceremony (#379).
    @discardableResult
    public func pair(
        payload: HTDTReceiverPairingPayload,
        nowUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws -> PairedHTDTDestination {
        var document = try load()
        if let index = document.destinations.firstIndex(where: {
            $0.receiverInstanceID == payload.receiverInstanceID
        }) {
            let existing = document.destinations[index]
            let replacement = PairedHTDTDestination(
                destinationID: existing.destinationID,
                displayName: payload.displayName,
                receiverInstanceID: payload.receiverInstanceID,
                endpointURL: payload.endpointURL,
                capabilityEndpointURL: payload.capabilityEndpointURL,
                pinnedIdentity: payload.pinnedIdentity,
                projectRef: payload.projectRef,
                pairedAtUTC: nowUTC,
                lastSeenAtUTC: nowUTC,
                cachedCapability: nil
            )
            document.destinations[index] = replacement
            try save(document)
            return replacement
        }
        let record = PairedHTDTDestination(
            destinationID: UUID().uuidString.lowercased(),
            displayName: payload.displayName,
            receiverInstanceID: payload.receiverInstanceID,
            endpointURL: payload.endpointURL,
            capabilityEndpointURL: payload.capabilityEndpointURL,
            pinnedIdentity: payload.pinnedIdentity,
            projectRef: payload.projectRef,
            pairedAtUTC: nowUTC,
            lastSeenAtUTC: nowUTC,
            cachedCapability: nil
        )
        document.destinations.append(record)
        try save(document)
        return record
    }

    /// Deletes the pairing entirely.
    public func forget(destinationID: String) throws {
        var document = try load()
        document.destinations.removeAll {
            $0.destinationID == destinationID
        }
        try save(document)
    }

    /// Keeps the record but removes the destination from the active
    /// set — send UI no longer offers it (#379).
    public func revoke(destinationID: String) throws {
        var document = try load()
        guard let index = document.destinations.firstIndex(where: {
            $0.destinationID == destinationID
        }) else {
            throw HTDTPairingError.unknownDestination(destinationID)
        }
        let existing = document.destinations[index]
        document.destinations[index] = PairedHTDTDestination(
            destinationID: existing.destinationID,
            displayName: existing.displayName,
            receiverInstanceID: existing.receiverInstanceID,
            endpointURL: existing.endpointURL,
            capabilityEndpointURL: existing.capabilityEndpointURL,
            pinnedIdentity: existing.pinnedIdentity,
            projectRef: existing.projectRef,
            pairedAtUTC: existing.pairedAtUTC,
            lastSeenAtUTC: existing.lastSeenAtUTC,
            cachedCapability: existing.cachedCapability,
            revoked: true
        )
        try save(document)
    }

    /// Refreshes `last_seen_at` after a successful exchange.
    public func markSeen(
        destinationID: String,
        atUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws {
        var document = try load()
        guard let index = document.destinations.firstIndex(where: {
            $0.destinationID == destinationID
        }) else {
            return
        }
        let existing = document.destinations[index]
        document.destinations[index] = PairedHTDTDestination(
            destinationID: existing.destinationID,
            displayName: existing.displayName,
            receiverInstanceID: existing.receiverInstanceID,
            endpointURL: existing.endpointURL,
            capabilityEndpointURL: existing.capabilityEndpointURL,
            pinnedIdentity: existing.pinnedIdentity,
            projectRef: existing.projectRef,
            pairedAtUTC: existing.pairedAtUTC,
            lastSeenAtUTC: atUTC,
            cachedCapability: existing.cachedCapability,
            revoked: existing.revoked
        )
        try save(document)
    }

    /// Caches the latest fetched capability document with its fetch
    /// timestamp — the UI labels it as a cached snapshot (#374).
    public func updateCachedCapability(
        destinationID: String,
        snapshot: HTDTEndpointCapabilitySnapshot?
    ) throws {
        var document = try load()
        guard let index = document.destinations.firstIndex(where: {
            $0.destinationID == destinationID
        }) else {
            return
        }
        let existing = document.destinations[index]
        document.destinations[index] = PairedHTDTDestination(
            destinationID: existing.destinationID,
            displayName: existing.displayName,
            receiverInstanceID: existing.receiverInstanceID,
            endpointURL: existing.endpointURL,
            capabilityEndpointURL: existing.capabilityEndpointURL,
            pinnedIdentity: existing.pinnedIdentity,
            projectRef: existing.projectRef,
            pairedAtUTC: existing.pairedAtUTC,
            lastSeenAtUTC: existing.lastSeenAtUTC,
            cachedCapability: snapshot,
            revoked: existing.revoked
        )
        try save(document)
    }

    /// Active (non-revoked) pairings as named endpoint destinations.
    public func activeDestinations() throws -> [PairedHTDTDestination] {
        try load().destinations.filter { !$0.revoked }
    }

    /// Look up the pairing behind a queue-recorded destination id.
    public func destination(
        receiverInstanceID: String
    ) throws -> PairedHTDTDestination? {
        try load().destinations.first {
            $0.receiverInstanceID == receiverInstanceID && !$0.revoked
        }
    }

    private func save(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary)
        _ = try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: temporary, to: fileURL)
    }
}
