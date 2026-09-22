import Foundation

/// Cross-product authority-ownership classes (#405): the claim a
/// Capture-authored artifact makes, so observation, attestation,
/// imported reference, derived diagnostic, bounded field
/// reconciliation and project authority stay machine-distinct.
/// The canonical matrix lives in `docs/AUTHORITY_OWNERSHIP.md`;
/// new cross-product artifacts identify their class here rather than
/// growing per-feature provenance spellings.
public enum CaptureAuthorityClass: String, Codable, Sendable, CaseIterable {
    /// Direct field observation (label photo, visible cable endpoint,
    /// setting read-back, measured dimension, captured geometry).
    case observed
    /// Human assertion based on field inspection — evidence, not
    /// universal project truth ("this surface is gypsum drywall",
    /// "this is Front Left").
    case operatorAttested = "operator_attested"
    /// Intent supplied by HTDT or another document (planned target,
    /// expected instance, catalog snapshot, Mission requirement).
    /// Never becomes observed merely because Capture displays it.
    case importedReference = "imported_reference"
    /// Derived from acquisition evidence to help the operator
    /// (coverage/blur/legibility warning, registration residual,
    /// quality readiness). Not raw evidence, not a project decision.
    case captureDerivedDiagnostic = "capture_derived_diagnostic"
    /// A bounded user decision local to the field workflow — retains
    /// both source records plus the explicit user confirmation.
    case fieldReconciliation = "field_reconciliation"
    /// Project/design/evaluation authority — normally HTDT-owned;
    /// Capture does not create these records.
    case projectAuthority = "project_authority"

    /// Whether Capture may author records of this class — every class
    /// except HTDT-owned project authority.
    public var isCaptureAuthored: Bool {
        self != .projectAuthority
    }

    /// The product that owns the record's canonical interpretation
    /// after promotion (#405): imported reference and project
    /// authority originate in HTDT; everything else is authored in the
    /// field and reconciled downstream.
    public var canonicalOwnerAfterPromotion: String {
        switch self {
        case .importedReference, .projectAuthority:
            return "htdt"
        case .observed, .operatorAttested,
             .captureDerivedDiagnostic, .fieldReconciliation:
            return "capture_field_record"
        }
    }
}
