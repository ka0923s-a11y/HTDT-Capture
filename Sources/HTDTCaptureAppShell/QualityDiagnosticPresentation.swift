import Foundation
import HTDTCaptureCore

/// Shared localized presentation for quality diagnostics and resource
/// events. Every surface that names a finding — the Review
/// diagnostics list, the blocked-reasons affordances under the
/// finalization gate — goes through these functions so a diagnostic
/// never renders raw machine strings inside localized UI.

/// User-facing label for one resource event kind (the token a
/// `resource_error` diagnostic embeds as `kind: detail`).
func localizedResourceEventKindLabel(
    _ kind: CaptureResourceEventKind
) -> String {
    switch kind {
    case .thermalPressure:
        return String(localized: "Thermal pressure")
    case .memoryPressure:
        return String(localized: "Memory pressure")
    case .storagePressure:
        return String(localized: "Storage pressure")
    case .persistenceBacklog:
        return String(localized: "Persistence backlog")
    case .persistenceFailure:
        return String(localized: "Persistence failure")
    case .interruption:
        return String(localized: "Interruption")
    }
}

/// One localized line per sufficiency-gate failure — the persisted
/// diagnostic embeds the machine failure list, and each sub-gate
/// needs different operator advice (more coverage cannot fix a
/// confidence failure).
func localizedDepthSufficiencyFailure(
    _ failure: DepthSufficiencyFailure
) -> String {
    switch failure {
    case .noUsableSamples:
        return String(
            localized: "No usable depth samples were recorded — rescan with scene depth active."
        )
    case .validSamplesBelowMinimum:
        return String(
            localized: "Too few valid depth samples — hold the scan on surfaces longer."
        )
    case .bestFrameValidFractionBelowMinimum:
        return String(
            localized: "Depth was mostly invalid even in the best frame — get closer to solid surfaces."
        )
    case .spatialCoverageBelowMinimum:
        return String(
            localized: "Depth evidence covers too little of the scene — sweep the room more evenly."
        )
    case .confidentFractionBelowMinimum:
        return String(
            localized: "Depth confidence is too low — rescan well-lit, textured surfaces."
        )
    case .confidenceEvidenceMissing:
        return String(
            localized: "Depth confidence was not recorded — keep scene depth enabled while scanning."
        )
    }
}

private func depthSufficiencyFailures(
    in diagnostic: QualityDiagnostic
) -> [DepthSufficiencyFailure] {
    guard let tail = diagnostic.message.range(
        of: "sufficiency gate: ",
        options: .backwards
    ) else {
        return []
    }
    return diagnostic.message[tail.upperBound...]
        .split(separator: ",")
        .compactMap {
            DepthSufficiencyFailure(rawValue: String($0))
        }
}

/// Localized message for one quality diagnostic — unknown codes fall
/// back to the persisted message verbatim.
func localizedQualityDiagnosticMessage(
    _ diagnostic: QualityDiagnostic
) -> String {
    switch diagnostic.code {
    case "roomplan_not_completed":
        return String(
            localized: "RoomPlan capture has not completed successfully."
        )
    case "insufficient_mesh_anchors":
        return String(
            localized: "Active mesh anchor count is below the required minimum."
        )
    case "insufficient_evidence_frames":
        return String(
            localized: "Evidence frame count is below the required minimum."
        )
    case "depth_evidence_missing":
        return String(
            localized: "This quality ruleset requires at least one depth observation."
        )
    case "tracking_unavailable_observed":
        return String(
            localized: "AR tracking became unavailable during the capture."
        )
    case "tracking_limited_observed":
        return String(
            localized: "AR tracking was limited during part of the capture."
        )
    case "tracking_unavailable_unrecovered":
        return String(
            localized: "AR tracking became unavailable and never recovered."
        )
    case "tracking_unavailable_extended":
        return String(
            localized: "A recovered tracking-unavailable interval exceeded the recoverable duration for this ruleset."
        )
    case "tracking_unavailable_recovering":
        return String(
            localized: "Tracking recovered but has not yet stayed normal for the required stable interval."
        )
    case "tracking_unavailable_recovered":
        return String(
            localized: "AR tracking was briefly unavailable but recovered within the allowed policy."
        )
    case "tracking_coordinate_discontinuity":
        return String(
            localized: "The spatial coordinate space was reset during capture; earlier evidence may not line up."
        )
    case "depth_fallback_insufficient":
        let failures = depthSufficiencyFailures(in: diagnostic)
        let header = String(
            localized: "Retained scene-depth evidence does not satisfy the depth-fallback sufficiency policy:"
        )
        if failures.isEmpty {
            return header
        }
        let reasons = failures
            .map(localizedDepthSufficiencyFailure)
            .map { "• " + $0 }
            .joined(separator: "\n")
        return header + "\n" + reasons
    case "mesh_depth_fallback":
        return String(
            localized: "Mesh evidence is below minimum; retained scene depth is used as bounded fallback."
        )
    case "integrity_not_checked":
        return String(
            localized: "Bundle integrity must pass before finalization."
        )
    case "integrity_failed":
        return String(
            localized: "Bundle integrity validation failed."
        )
    case "resource_error":
        // Persisted as "kind: detail" — localize the kind token and
        // keep the technical detail as the secondary text.
        let parts = diagnostic.message.split(
            separator: ":",
            maxSplits: 1
        )
        if let first = parts.first,
           let kind = CaptureResourceEventKind(
               rawValue: String(first)
           )
        {
            let detail = parts.count > 1
                ? String(parts[1])
                    .trimmingCharacters(in: .whitespaces)
                : ""
            return detail.isEmpty
                ? localizedResourceEventKindLabel(kind)
                : localizedResourceEventKindLabel(kind) + ": " + detail
        }
        return diagnostic.message
    default:
        return diagnostic.message
    }
}
