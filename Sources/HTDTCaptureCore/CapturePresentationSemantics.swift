import Foundation

/// Semantic color roles for the shared GUI design system (#361/#364).
///
/// These are *roles*, not brand colors: AppShell maps each role to a
/// system color so light/dark appearance and Dynamic Type contrast stay
/// platform-managed. Screens must not pick ad-hoc per-view colors for a
/// state this vocabulary already covers; direct color use is reserved
/// for domain visualizations (e.g. the spatial coverage map legend).
public enum CaptureColorRole:
    String,
    Sendable,
    Equatable,
    CaseIterable
{
    /// Primary action / selected element.
    case accent
    /// Ready, complete, verified, pass.
    case success
    /// Advisory, needs review, low-resource, attention.
    case attention
    /// Blocked, failure, destructive.
    case blocked
    /// Informational (never implies success).
    case informational
    /// Unknown or unavailable state.
    case unknown
    /// Derived/advisory preview — evidence that is inferred, not
    /// measured; never the same color as an error.
    case derived
    /// Muted secondary information.
    case secondary
}

/// The canonical presentation status vocabulary (#361/#364 §13).
///
/// Every status resolves to symbol + human label + color role so no
/// state is ever conveyed by color alone. `label` returns the
/// development-language (English) string; the AppShell design
/// components localize through the app string tables, keeping this
/// file free of SwiftUI so the vocabulary stays unit-testable in
/// `swift test`.
public enum CaptureSemanticStatus:
    String,
    Sendable,
    Equatable,
    CaseIterable
{
    case ready
    case needsReview
    case incomplete
    case blocked
    case pending
    case unavailable
    case unknown
    case draft
    case finalized
    case imported
    case derived
    case advisory
    case verified
    case skipped

    /// English (development-language) label. AppShell renders it via
    /// `LocalizedStringKey`-aware components so the same copy resolves
    /// through `Localizable.strings` for Japanese.
    public var labelKey: String {
        switch self {
        case .ready: return "Ready"
        case .needsReview: return "Needs review"
        case .incomplete: return "Incomplete"
        case .blocked: return "Blocked"
        case .pending: return "Pending"
        case .unavailable: return "Unavailable"
        case .unknown: return "Unknown"
        case .draft: return "Draft"
        case .finalized: return "Finalized"
        case .imported: return "Imported"
        case .derived: return "Derived"
        case .advisory: return "Advisory"
        case .verified: return "Verified"
        case .skipped: return "Skipped"
        }
    }

    /// SF Symbol paired with the label — status is never color-only.
    public var symbolName: String {
        switch self {
        case .ready, .verified:
            return "checkmark.circle.fill"
        case .needsReview, .advisory:
            return "exclamationmark.triangle.fill"
        case .incomplete:
            return "circle.dashed"
        case .blocked:
            return "xmark.octagon.fill"
        case .pending:
            return "clock"
        case .unavailable:
            return "slash.circle"
        case .unknown:
            return "questionmark.circle"
        case .draft:
            return "doc.badge.clock"
        case .finalized:
            return "lock.fill"
        case .imported:
            return "square.and.arrow.down.fill"
        case .derived:
            return "wand.and.stars"
        case .skipped:
            return "forward.fill"
        }
    }

    public var colorRole: CaptureColorRole {
        switch self {
        case .ready, .verified:
            return .success
        case .needsReview, .advisory, .pending:
            return .attention
        case .blocked:
            return .blocked
        case .incomplete:
            return .attention
        case .unavailable, .unknown:
            return .unknown
        case .draft:
            return .attention
        case .finalized:
            return .accent
        case .imported:
            return .informational
        case .derived:
            return .derived
        case .skipped:
            return .secondary
        }
    }
}

/// One required-action or advisory notice for the capture-first home
/// screen (#360): the landing surface shows device readiness only when
/// the operator must act, instead of permanent telemetry rows.
public enum CaptureHomeNotice:
    Sendable,
    Equatable
{
    /// Camera permission denied or restricted — capture cannot start
    /// until the operator changes iOS Settings.
    case cameraAccessRequired
    /// The device cannot run the canonical RoomPlan+mesh capture mode.
    case deviceUnsupported
    /// Free storage is critically low.
    case storageCritical
    /// An end-accepted capture draft survived an interruption (#437)
    /// — the persistent stranded-draft indicator. Carries the draft
    /// count.
    case interruptedCapture(draftCount: Int)
    /// Quarantined artifacts, orphaned working data, or enumeration
    /// failures need bounded cleanup. Carries the item count.
    case libraryMaintenance(itemCount: Int)

    /// Heading shown in the notice row.
    public var titleKey: String {
        switch self {
        case .cameraAccessRequired:
            return "Camera access is required"
        case .deviceUnsupported:
            return "This device cannot scan"
        case .storageCritical:
            return "Not enough free storage"
        case .interruptedCapture:
            return "Interrupted capture"
        case .libraryMaintenance:
            return "Library maintenance needed"
        }
    }

    /// Plain-language explanation and the suggested next step.
    public var messageKey: String {
        switch self {
        case .cameraAccessRequired:
            return "Enable camera access in Settings to scan a room."
        case .deviceUnsupported:
            return "Use a supported LiDAR-capable iPhone or iPad for this capture workflow."
        case .storageCritical:
            return "Free device storage before starting a capture."
        case .interruptedCapture:
            return "A capture ended or was interrupted before it was saved. Its data is kept as a draft — reopen it to finish, or discard it."
        case .libraryMaintenance:
            return "Interrupted capture data needs attention."
        }
    }

    public var status: CaptureSemanticStatus {
        switch self {
        case .cameraAccessRequired, .deviceUnsupported,
             .storageCritical:
            return .blocked
        case .interruptedCapture:
            return .draft
        case .libraryMaintenance:
            return .needsReview
        }
    }
}

/// Computes the home-screen presentation (#360): which readiness
/// notices are visible, and whether New capture is enabled. Pure value
/// mapping so the information hierarchy stays unit-testable.
public enum CaptureHomePresentation {
    /// Ordered home notices. The stranded-draft indicator comes
    /// first — its data is only safe once the operator decides —
    /// then camera/permission problems, storage, library maintenance
    /// last.
    public static func notices(
        cameraPermissionDenied: Bool,
        cameraPermissionRestricted: Bool,
        deviceCaptureEligible: Bool,
        storageReadiness: CaptureStorageReadiness,
        maintenanceItemCount: Int,
        recoverableDraftCount: Int = 0
    ) -> [CaptureHomeNotice] {
        var notices: [CaptureHomeNotice] = []
        if recoverableDraftCount > 0 {
            notices.append(
                .interruptedCapture(
                    draftCount: recoverableDraftCount
                )
            )
        }
        if cameraPermissionDenied || cameraPermissionRestricted {
            notices.append(.cameraAccessRequired)
        }
        if !deviceCaptureEligible {
            notices.append(.deviceUnsupported)
        }
        if storageReadiness == .critical {
            notices.append(.storageCritical)
        }
        if maintenanceItemCount > 0 {
            notices.append(
                .libraryMaintenance(
                    itemCount: maintenanceItemCount
                )
            )
        }
        return notices
    }

    /// Total maintenance items from a persisted-inventory scan:
    /// quarantined artifacts + orphaned working data + enumeration
    /// failures.
    public static func maintenanceItemCount(
        _ inventory: PersistedCaptureInventoryResult
    ) -> Int {
        inventory.quarantinedArtifacts.count
            + inventory.orphanedWorkingArtifacts.count
            + inventory.enumerationFailures.count
    }
}

/// The pure layout-adaptation rule (#362): two-pane compositions are
/// allowed on regular width — iPad regular size class, a wide Stage
/// Manager or macOS window — decided by *available* width, never a
/// device-name check. Very large Dynamic Type always falls back to the
/// single-column composition so neither pane clips.
public enum CaptureAdaptiveLayoutDecision {
    /// Width below which a layout is treated as compact even when the
    /// platform reports no size class (macOS / arbitrary windows).
    public static let compactWidthLimit: CGFloat = 700

    public static func prefersPanes(
        isRegularWidthClass: Bool,
        availableWidth: CGFloat,
        isAccessibilityDynamicType: Bool
    ) -> Bool {
        guard !isAccessibilityDynamicType else {
            return false
        }
        return isRegularWidthClass
            || availableWidth >= compactWidthLimit
    }
}

/// The series-first visual identity of one library entry (#360):
/// human name first, then recency + revision count + concise status;
/// the raw revision/series UUIDs are detail-level provenance, never
/// the default visible identity.
public struct CaptureSeriesPresentation:
    Sendable,
    Equatable
{
    /// Primary visible identity: the operator-assigned name, or a
    /// stable non-UUID fallback for unnamed series.
    public let title: String
    /// True when `title` is an operator name (not a fallback).
    public let isNamed: Bool
    /// "3 revisions" style count, or "1 revision".
    public let revisionSummary: String
    /// Short localized date of the latest revision, nil when the
    /// timestamp could not be parsed.
    public let latestDateLabel: String?
    /// Concise library status for the series' latest revision.
    public let status: CaptureSemanticStatus
    /// Optional operator note shown as secondary text.
    public let note: String?

    public init(
        group: CaptureSeriesGroup,
        revisionMetadata: CaptureLibraryEntryMetadata?,
        locale: Locale = .autoupdatingCurrent
    ) {
        if let name = group.displayName, !name.isEmpty {
            title = name
            isNamed = true
        } else if let name = revisionMetadata?.displayName,
                  !name.isEmpty
        {
            title = name
            isNamed = true
        } else {
            title = String(localized: "Unnamed series")
            isNamed = false
        }
        note = revisionMetadata?.note ?? group.metadata?.note
        let count = group.revisions.count
        revisionSummary = count == 1
            ? String(localized: "1 revision")
            : String(
                format: String(localized: "%d revisions"),
                count
            )
        latestDateLabel = Self.dateLabel(
            for: group.latestRevision?.finalizedAtUTC,
            locale: locale
        )
        status = Self.status(for: group.latestRevision)
    }

    /// The concise status a single revision presents in the library:
    /// finalized bundles are the normal case; an export-archive-only
    /// record presents as Imported.
    public static func status(
        for record: PersistedCaptureRecord?
    ) -> CaptureSemanticStatus {
        guard let record else {
            return .unknown
        }
        if record.canOpen {
            return .finalized
        }
        return .imported
    }

    /// Short localized date ("Sep 22, 2026") for the canonical
    /// `finalized_at` UTC timestamp, or nil when unparseable.
    public static func dateLabel(
        for utcString: String?,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let utcString, !utcString.isEmpty else {
            return nil
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [
            .withInternetDateTime,
        ]
        var date = plain.date(from: utcString)
        if date == nil {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds,
            ]
            date = fractional.date(from: utcString)
        }
        guard let date else { return nil }
        return date.formatted(
            .dateTime
                .locale(locale)
                .day().month(.abbreviated).year()
        )
    }
}

// MARK: - Operator copy helpers (#442/#443)

/// Chooses the singular or plural localized format string for a
/// count-bearing message (#442). The raw `"(s)"` idiom never reaches
/// the operator: each call site passes two complete format strings —
/// one per grammatical form — so the localization audit extracts a
/// full, translatable sentence for each. Both take the count as their
/// single numeric argument.
public func captureCountPhrase(
    _ count: Int,
    singular: String,
    plural: String
) -> String {
    String(format: count == 1 ? singular : plural, count)
}

/// Humanizes a wire token (`"a_b"` → "a b") as a last-resort display
/// string where a dedicated localized label does not exist yet (#443).
public func captureHumanizedToken(_ token: String) -> String {
    token
        .replacingOccurrences(of: "_", with: " ")
        .trimmingCharacters(in: .whitespaces)
}

/// Localized display name for a recoverable working-revision phase
/// (#441): draft rows lead with this rather than the stored UUID.
public func workingRevisionPhaseName(
    _ phase: WorkingRevisionPhase
) -> String {
    switch phase {
    case .liveScanIncomplete:
        return String(localized: "Scan interrupted")
    case .endAccepted:
        return String(localized: "Ended; ready for review")
    case .semanticAuthoring:
        return String(localized: "Ended; annotations in progress")
    case .readyToFinalize:
        return String(localized: "Ready to finalize")
    }
}

/// Localized display name for a plan-underlay alignment method
/// (#443): the raw `alignment.method` enum token never reaches the
/// operator.
public func planUnderlayAlignmentMethodName(
    _ method: PlanUnderlayAlignmentMethod
) -> String {
    switch method {
    case .htdtDatum:
        return String(localized: "HTDT datum alignment")
    case .referencePointPair:
        return String(localized: "Reference point pair")
    case .knownDistanceAxis:
        return String(localized: "Known distance axis")
    case .fiducialAlignment:
        return String(localized: "Fiducial marker alignment")
    }
}

/// Localized display name for the session's geometry-evidence mode
/// (#443), tolerating a missing summary value.
public func observationGeometryEvidenceModeName(
    _ mode: ObservationGeometryEvidenceMode?
) -> String {
    switch mode {
    case .some(.none):
        return String(localized: "No geometry evidence")
    case .some(.depthOnly):
        return String(localized: "Depth evidence only")
    case .some(.meshOnly):
        return String(localized: "RoomPlan mesh only")
    case .some(.meshAndDepth):
        return String(localized: "RoomPlan mesh + depth")
    case nil:
        return String(localized: "Unknown")
    }
}

/// Localized display name for the movement capability guidance
/// recorded during the scan (#443).
public func scanMovementCapabilityName(
    _ capability: ScanMovementCapability?
) -> String {
    switch capability {
    case .some(.unrestricted):
        return String(localized: "Free movement")
    case .some(.stationaryOnly):
        return String(localized: "Stationary only")
    case .some(.safetyConstrained):
        return String(localized: "Movement marked unsafe")
    case nil:
        return String(localized: "Unknown")
    }
}

/// Localized display name for a directional reference convention
/// (#443): `"start_relative"` is the only convention producers emit
/// today; unknown tokens degrade to a humanized phrase rather than a
/// raw wire value.
public func directionReferenceName(_ raw: String) -> String {
    switch raw {
    case "start_relative":
        return String(localized: "Start direction")
    default:
        let humanized = captureHumanizedToken(raw)
        return humanized.isEmpty
            ? String(localized: "Unknown")
            : humanized
    }
}

/// Localized display name for an HTDT equipment-catalog identity
/// kind (#443) — `user_defined` reads "User defined", never the raw
/// wire token.
public func equipmentIdentityKindName(
    _ kind: HTDTEquipmentIdentityKind
) -> String {
    switch kind {
    case .manufacturer:
        return String(localized: "Manufacturer")
    case .userDefined:
        return String(localized: "User defined")
    }
}
