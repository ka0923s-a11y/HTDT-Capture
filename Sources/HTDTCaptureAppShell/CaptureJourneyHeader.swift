import Foundation
import SwiftUI
import HTDTCaptureCore

/// The capture-loop header (issue #372): Prepare → Scan → Review →
/// Details → Finalize → Send presented as one loop-aware journey —
/// never a rigid linear stepper. Compact width shows the current
/// stage plus its subtitle; regular width shows the whole trail with
/// per-stage statuses derived from real workflow facts.
public struct CaptureJourneyHeader: View {
    public let presentation: CaptureJourneyPresentation

    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    public init(presentation: CaptureJourneyPresentation) {
        self.presentation = presentation
    }

    /// The journey trail — Home is the idle library, never a step in
    /// the capture loop itself.
    private var trailStages: [CaptureJourneyStage] {
        CaptureJourneyStage.allCases.filter { $0 != .home }
    }

    public var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                expandedTrail
            } else {
                compactStage
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Compact (iPhone)

    private var compactStage: some View {
        VStack(
            alignment: .leading,
            spacing: CaptureDesign.Spacing.micro
        ) {
            HStack(spacing: CaptureDesign.Spacing.row) {
                Image(
                    systemName: statusSymbol(
                        presentation.status(
                            for: presentation.currentStage
                        )
                    )
                )
                .foregroundStyle(
                    presentation.status(
                        for: presentation.currentStage
                    ).colorRole.color
                )
                Text(stageTitle)
                    .font(CaptureDesign.Typography.taskHeadline)
                if presentation.isFailed {
                    Text(
                        LocalizedStringKey(
                            CaptureJourneyStageStatus.failed.labelKey
                        )
                    )
                    .font(CaptureDesign.Typography.secondary)
                    .foregroundStyle(CaptureColorRole.blocked.color)
                }
            }
            if let transient = presentation.transientLabelKey {
                Text(LocalizedStringKey(transient))
                    .font(CaptureDesign.Typography.secondary)
                    .foregroundStyle(.secondary)
            } else if !presentation.subtitleKey.isEmpty {
                Text(LocalizedStringKey(presentation.subtitleKey))
                    .font(CaptureDesign.Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            if let mission = presentation.mission {
                Text(
                    String(
                        format: String(
                            localized: "Required tasks %lld/%lld"
                        ),
                        mission.requiredCompleted,
                        mission.requiredTotal
                    )
                )
                .font(CaptureDesign.Typography.secondary)
                .foregroundStyle(.secondary)
            }
            readinessRow
        }
    }

    // MARK: - Expanded (iPad / regular width)

    private var expandedTrail: some View {
        VStack(
            alignment: .leading,
            spacing: CaptureDesign.Spacing.micro
        ) {
            HStack(spacing: CaptureDesign.Spacing.row) {
                ForEach(trailStages, id: \.self) { stage in
                    let status = presentation.status(for: stage)
                    HStack(spacing: CaptureDesign.Spacing.micro) {
                        Image(systemName: status.symbolName)
                            .foregroundStyle(status.colorRole.color)
                        Text(LocalizedStringKey(stage.titleKey))
                            .font(CaptureDesign.Typography.secondary)
                            .foregroundStyle(
                                status == .current
                                    ? .primary : .secondary
                            )
                    }
                    .accessibilityElement(children: .combine)
                    if stage != trailStages.last {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                }
            }
            HStack(spacing: CaptureDesign.Spacing.group) {
                if let transient = presentation.transientLabelKey {
                    Text(LocalizedStringKey(transient))
                } else if !presentation.subtitleKey.isEmpty {
                    Text(LocalizedStringKey(presentation.subtitleKey))
                }
                if let mission = presentation.mission {
                    Text(
                        String(
                            format: String(
                                localized: "Required tasks %lld/%lld"
                            ),
                            mission.requiredCompleted,
                            mission.requiredTotal
                        )
                    )
                }
            }
            .font(CaptureDesign.Typography.secondary)
            .foregroundStyle(.secondary)
            readinessRow
        }
    }

    /// Technical readiness — integrity + spatial persistence — kept
    /// visibly separate from mission progress (#372 JOURNEY-50).
    @ViewBuilder
    private var readinessRow: some View {
        if let readiness = presentation.readiness {
            HStack(spacing: CaptureDesign.Spacing.group) {
                if let ready = readiness.integrityReady {
                    LabeledContent("Integrity") {
                        CaptureStatusView(
                            ready ? .ready : .blocked
                        )
                    }
                }
                LabeledContent("Spatial data") {
                    CaptureStatusView(
                        readiness.spatialCapturePersisted
                            ? .verified : .pending
                    )
                }
            }
        }
    }

    private var stageTitle: String {
        String(
            localized: String.LocalizationValue(
                presentation.currentStage.pageTitleKey
            )
        )
    }

    private func statusSymbol(
        _ status: CaptureJourneyStageStatus
    ) -> String {
        status.symbolName
    }

    /// VoiceOver: "Current step: Review. Scan complete. Two required
    /// tasks remaining." (issue #372 JOURNEY-90).
    private var accessibilitySummary: String {
        var parts = [
            String(
                format: String(localized: "Current step: %@."),
                stageTitle
            ),
        ]
        if let transient = presentation.transientLabelKey {
            parts.append(
                String(
                    localized: String.LocalizationValue(transient)
                )
            )
        } else if !presentation.subtitleKey.isEmpty {
            parts.append(
                String(
                    localized: String.LocalizationValue(
                        presentation.subtitleKey
                    )
                )
            )
        }
        if let mission = presentation.mission,
           mission.outstanding > 0
        {
            parts.append(
                String(
                    format: String(
                        localized: "%lld required tasks remaining."
                    ),
                    mission.outstanding
                )
            )
        }
        return parts.joined(separator: " ")
    }
}
