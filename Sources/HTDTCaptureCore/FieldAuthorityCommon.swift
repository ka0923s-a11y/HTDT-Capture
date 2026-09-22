import Foundation

/// Shared grammar helpers for the field-authority document family
/// (issues #300, #301, #310, #314, #324, #331): operator profiles,
/// typed field evidence, measurement-instrument profiles, installed
/// settings observations, and as-built wiring routes.
enum FieldAuthorityGrammar {
    /// Binding-ref namespaces carrying a canonical UUIDv4 identifier.
    static let uuidNamespaces: Set<String> = [
        "entity",
        "measurement",
        "capture_revision",
        "capture_session",
        "inventory_item",
        "wiring_route",
        "settings_observation",
        "instrument",
        "operator",
        "field_evidence",
    ]
    /// Binding-ref namespaces carrying an opaque non-empty identifier
    /// (task-plan items, commissioning checks, catalog equipment ids,
    /// calibration-plan items, surface/anchor references).
    static let tokenNamespaces: Set<String> = [
        "task_item",
        "commissioning_check",
        "equipment",
        "calibration_plan_item",
        "surface",
        "mesh_anchor",
        "path",
    ]

    /// True when `ref` is `ns:id` where `ns` names a UUIDv4 namespace
    /// with canonical lowercase text or a token namespace with a
    /// printable-ASCII identifier of at most 512 bytes.
    static func isBindingRef(_ ref: String) -> Bool {
        guard let colon = ref.firstIndex(of: ":") else {
            return false
        }
        let namespace = String(ref[..<colon])
        let identifier = String(ref[ref.index(after: colon)...])
        guard !identifier.isEmpty else {
            return false
        }
        if uuidNamespaces.contains(namespace) {
            return UUID(canonicalUUIDv4Text: identifier) != nil
        }
        guard tokenNamespaces.contains(namespace) else {
            return false
        }
        guard identifier.utf8.count <= 512,
              identifier.unicodeScalars.allSatisfy({
                  $0.value >= 0x21 && $0.value <= 0x7E
              })
        else {
            return false
        }
        return true
    }

    /// Evidence refs additionally allow `frame:<uuid4>` (canonical scan
    /// frame shorthand) and `sha256:<64-hex>` (a retained artifact's
    /// digest, e.g. a calibration certificate kept outside the bundle).
    static func isEvidenceRef(_ ref: String) -> Bool {
        if isBindingRef(ref) {
            return true
        }
        if ref.hasPrefix("frame:") {
            return UUID(
                canonicalUUIDv4Text: String(
                    ref.dropFirst("frame:".count)
                )
            ) != nil
        }
        if ref.hasPrefix("sha256:") {
            let hex = String(ref.dropFirst("sha256:".count))
            return hex.count == 64
                && hex.unicodeScalars.allSatisfy {
                    ($0.value >= 0x30 && $0.value <= 0x39)
                        || ($0.value >= 0x61 && $0.value <= 0x66)
                }
        }
        return false
    }

    /// Lowercase machine token (`[a-z0-9_]+`) used for cable types,
    /// setting parameters and similar enumerated-by-convention fields.
    static func isLowercaseToken(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            ($0.value >= 0x61 && $0.value <= 0x7A)
                || ($0.value >= 0x30 && $0.value <= 0x39)
                || $0.value == 0x5F
        }
    }
}

/// Canonical JSON encoding shared by every field-authority package
/// writer (sorted keys, unescaped slashes — the bundle canonical
/// profile for JSON payloads).
enum FieldAuthorityCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        return encoder
    }
}

public enum FieldAuthorityModelError: Error, Sendable, Equatable {
    case emptyField(String)
    case invalidBindingRef(String)
    case invalidToken(String)
    case invalidTimestamp(String)
    case invalidCalendarDate(String)
    case duplicateRecord(String)
    case unboundReference(String)
    case attestationRequired
    case missingAssetAuthority
    case invalidAssetPath(String)
    case invalidObservedValue
    case invalidCalibrationWindow
    case unknownInstrumentVersion
    case endpointConflict
    case hiddenPathGuess
}
