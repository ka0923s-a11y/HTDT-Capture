import Foundation
import SwiftUI
import HTDTCaptureCore

public struct CaptureScanningView: View {
    public let preview: AnyView
    public let coverage: ScanCoverageSummary
    public let observation: ObservationStabilitySummary
    public let spatialCoverage: SpatialScanCoverageSummary
    public let motionGuidance: ScanMotionGuidance?
    public let guidanceProgress: ScanGuidanceProgress
    public let derivedPreview: DerivedShapePreviewSnapshot
    public let evidenceFrameCount: Int
    public let statusMessage: String?
    public let endScanGuidance: String?
    public let captureEvidenceFrame: () -> Void
    public let setMovementCapability:
        (ScanMovementCapability) -> Void
    public let endScan: () -> Void
    /// True while the host is committing the End transaction (#279):
    /// scan controls are replaced with an explicit busy state instead
    /// of looking actionable while actions are internally no-op.
    public let isEndingScan: Bool
    /// True while a manual evidence save is still in flight.
    public let isCapturingEvidence: Bool
    /// Frames retained by the bounded automatic selector (#216).
    public let automaticEvidenceCount: Int
    /// Live low-light recovery surface (#283).
    public let lowLightGuidanceActive: Bool
    /// Active targeted-object pass status (#250).
    public let targetScanStatus: TargetScanStatus?
    /// Operator-declared unresolved regions (#257).
    public let declaredRegions: [DeclaredCoverageRegion]
    /// Return-to-start check state (#273).
    public let loopClosureCheckActive: Bool
    public let loopClosureAssessment: LoopClosureAssessment?
    /// Non-visual guidance cue master switch (#252).
    public let guidanceCuesEnabled: Bool
    /// Unresolved revisit flags dropped during this scan (#325).
    public let revisitFlagCount: Int
    /// True when the bounded flag store is full — the flag control
    /// stays visible but disabled.
    public let revisitFlagsFull: Bool
    /// One-tap revisit-flag drop (#325). Returns the new flag id when
    /// persisted so the view can offer the optional details sheet, nil
    /// when the flag could not be recorded.
    public let flagForReview: () -> String?
    /// Saves the optional flag category/note from the post-flag sheet.
    public let updateRevisitFlagDetails:
        (String, ScanRevisitFlagCategory?, String?) -> Void
    public let beginTargetScan: () -> Void
    public let retakeTargetScan: () -> Void
    public let acceptTargetScan: () -> Void
    public let cancelTargetScan: () -> Void
    public let declareNearestUnresolvedRegion:
        (DeclaredRegionReason) -> Void
    public let revokeOperatorRegion:
        (SpatialCoverageCellKey) -> Void
    public let setGuidanceCuesEnabled: (Bool) -> Void
    public let setLoopClosureCheckActive: (Bool) -> Void

    @State private var showingEndScanReview = false
    @State private var isHUDExpanded = false
    @State private var showingAuthorityHelp = false
    @State private var showingSpatialMap = false
    @State private var showingDerivedPreview = false
    @State private var derivedPreviewMode: DerivedPreviewMode = .observation
    /// #325: the flag whose optional details sheet is open.
    @State private var flagDetailsID: String?
    @State private var flagDetailsCategory: ScanRevisitFlagCategory?
    @State private var flagDetailsNote = ""

    public init(
        preview: AnyView,
        coverage: ScanCoverageSummary,
        observation: ObservationStabilitySummary,
        spatialCoverage: SpatialScanCoverageSummary,
        motionGuidance: ScanMotionGuidance?,
        guidanceProgress: ScanGuidanceProgress,
        derivedPreview: DerivedShapePreviewSnapshot,
        evidenceFrameCount: Int,
        statusMessage: String? = nil,
        endScanGuidance: String? = nil,
        isEndingScan: Bool = false,
        isCapturingEvidence: Bool = false,
        automaticEvidenceCount: Int = 0,
        lowLightGuidanceActive: Bool = false,
        targetScanStatus: TargetScanStatus? = nil,
        declaredRegions: [DeclaredCoverageRegion] = [],
        loopClosureCheckActive: Bool = false,
        loopClosureAssessment: LoopClosureAssessment? = nil,
        guidanceCuesEnabled: Bool = true,
        revisitFlagCount: Int = 0,
        revisitFlagsFull: Bool = false,
        flagForReview: @escaping () -> String? = { nil },
        updateRevisitFlagDetails: @escaping
            (String, ScanRevisitFlagCategory?, String?) -> Void
            = { _, _, _ in },
        beginTargetScan: @escaping () -> Void = {},
        retakeTargetScan: @escaping () -> Void = {},
        acceptTargetScan: @escaping () -> Void = {},
        cancelTargetScan: @escaping () -> Void = {},
        declareNearestUnresolvedRegion: @escaping
            (DeclaredRegionReason) -> Void = { _ in },
        revokeOperatorRegion: @escaping
            (SpatialCoverageCellKey) -> Void = { _ in },
        setGuidanceCuesEnabled: @escaping
            (Bool) -> Void = { _ in },
        setLoopClosureCheckActive: @escaping
            (Bool) -> Void = { _ in },
        captureEvidenceFrame: @escaping () -> Void,
        setMovementCapability: @escaping
            (ScanMovementCapability) -> Void,
        endScan: @escaping () -> Void
    ) {
        self.preview = preview
        self.coverage = coverage
        self.observation = observation
        self.spatialCoverage = spatialCoverage
        self.motionGuidance = motionGuidance
        self.guidanceProgress = guidanceProgress
        self.derivedPreview = derivedPreview
        self.evidenceFrameCount = evidenceFrameCount
        self.statusMessage = statusMessage
        self.endScanGuidance = endScanGuidance
        self.isEndingScan = isEndingScan
        self.isCapturingEvidence = isCapturingEvidence
        self.automaticEvidenceCount = automaticEvidenceCount
        self.lowLightGuidanceActive = lowLightGuidanceActive
        self.targetScanStatus = targetScanStatus
        self.declaredRegions = declaredRegions
        self.loopClosureCheckActive = loopClosureCheckActive
        self.loopClosureAssessment = loopClosureAssessment
        self.guidanceCuesEnabled = guidanceCuesEnabled
        self.revisitFlagCount = revisitFlagCount
        self.revisitFlagsFull = revisitFlagsFull
        self.flagForReview = flagForReview
        self.updateRevisitFlagDetails = updateRevisitFlagDetails
        self.beginTargetScan = beginTargetScan
        self.retakeTargetScan = retakeTargetScan
        self.acceptTargetScan = acceptTargetScan
        self.cancelTargetScan = cancelTargetScan
        self.declareNearestUnresolvedRegion =
            declareNearestUnresolvedRegion
        self.revokeOperatorRegion = revokeOperatorRegion
        self.setGuidanceCuesEnabled = setGuidanceCuesEnabled
        self.setLoopClosureCheckActive =
            setLoopClosureCheckActive
        self.captureEvidenceFrame = captureEvidenceFrame
        self.setMovementCapability = setMovementCapability
        self.endScan = endScan
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                preview
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    compactStatusHUD
                        .padding(.horizontal, 10)
                        .padding(.top, 6)

                    Spacer(minLength: 12)

                    if isHUDExpanded {
                        expandedHUD(
                            maxHeight: geometry.size.height * 0.36
                        )
                        .padding(.horizontal, 10)
                        .transition(
                            .move(edge: .bottom)
                                .combined(with: .opacity)
                        )
                    }

                    compactBottomControls
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }

                if let motionGuidance {
                    motionGuidanceOverlay(motionGuidance)
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height * 0.43
                        )
                        .allowsHitTesting(false)
                }

                if isEndingScan {
                    finishingCaptureOverlay
                        .allowsHitTesting(true)
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(
            .easeInOut(duration: 0.20),
            value: isHUDExpanded
        )
        .sheet(isPresented: $showingEndScanReview) {
            ScanCoverageEndReview(
                coverage: coverage,
                spatialCoverage: spatialCoverage,
                continueScanning: {
                    showingEndScanReview = false
                },
                endAnyway: {
                    showingEndScanReview = false
                    endScan()
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingAuthorityHelp) {
            authorityHelpView
                .presentationDetents([.medium, .large])
        }
        .sheet(
            isPresented: Binding(
                get: { flagDetailsID != nil },
                set: { isPresented in
                    if !isPresented {
                        flagDetailsID = nil
                    }
                }
            )
        ) {
            revisitFlagDetailsSheet
                .presentationDetents([.medium])
        }
    }

    /// #325: the optional post-flag details sheet. Dropping a flag is
    /// a single tap during scanning; category/note are offered only
    /// afterwards, when the operator has stopped to interact — and the
    /// scan keeps running either way.
    private var revisitFlagDetailsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        "What needs review?",
                        selection: $flagDetailsCategory
                    ) {
                        Text("Not set")
                            .tag(
                                ScanRevisitFlagCategory?.none
                            )
                        ForEach(
                            ScanRevisitFlagCategory.allCases,
                            id: \.self
                        ) { category in
                            Text(revisitFlagCategoryLabel(category))
                                .tag(
                                    ScanRevisitFlagCategory?
                                        .some(category)
                                )
                        }
                    }

                    TextField(
                        "Short note (optional)",
                        text: $flagDetailsNote,
                        axis: .vertical
                    )
                    .lineLimit(2 ... 4)
                } footer: {
                    Text(
                        "The flag is already saved and will be listed in Review. Details are optional and can be added while you stay put."
                    )
                }
            }
            .navigationTitle("Flag for review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        flagDetailsID = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save details") {
                        if let flagDetailsID {
                            updateRevisitFlagDetails(
                                flagDetailsID,
                                flagDetailsCategory,
                                flagDetailsNote.isEmpty
                                ? nil
                                : flagDetailsNote
                            )
                        }
                        flagDetailsID = nil
                    }
                }
            }
        }
    }

    private func revisitFlagCategoryLabel(
        _ category: ScanRevisitFlagCategory
    ) -> String {
        switch category {
        case .geometry:
            return String(localized: "Geometry")
        case .opening:
            return String(localized: "Opening")
        case .reflectiveTransparent:
            return String(
                localized: "Reflective / transparent"
            )
        case .objectDetail:
            return String(localized: "Object detail")
        case .measurement:
            return String(localized: "Measurement")
        case .equipment:
            return String(localized: "Equipment")
        case .other:
            return String(localized: "Other")
        }
    }

    private var compactStatusHUD: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(
                    trackingLabel,
                    systemImage: trackingSystemImage
                )
                .font(.caption.weight(.semibold))
                .lineLimit(1)

                Spacer(minLength: 6)

                Text(
                    String(
                        format: String(localized: "Direction %d%%"),
                        coveragePercent
                    )
                )
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)

                Button {
                    showingAuthorityHelp = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Details"))

                Button {
                    withAnimation(
                        .easeInOut(duration: 0.20)
                    ) {
                        isHUDExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(
                            systemName:
                                isHUDExpanded
                                ? "chevron.down"
                                : "chevron.up"
                        )
                        Text(
                            isHUDExpanded
                            ? String(localized: "Close")
                            : String(localized: "Details")
                        )
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let motionGuidance {
                Text(
                    primaryScanReadyToEnd
                    ? String(localized: "Optional extra observation")
                    : ScanMotionGuidanceCopy.category(
                        for: motionGuidance.action,
                        language:
                            ScanMotionGuidanceCopy.preferredLanguage
                    )
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Text(actionSentence)
                .font(.headline.weight(.semibold))
                .foregroundStyle(
                    endScanGuidance == nil
                    ? Color.primary
                    : Color.orange
                )
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

            // #313: translation prompts always carry the safety
            // qualifier inline; the note reminds the operator the app
            // cannot verify their path.
            if let motionGuidance,
               let note = ScanMotionGuidanceCopy.safetyNote(
                for: motionGuidance,
                language: ScanMotionGuidanceCopy.preferredLanguage
               )
            {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            // #283: the low-light prompt is a distinct surface, not
            // folded into generic tracking wording.
            if lowLightGuidanceActive {
                Label(
                    "The room is too dark for reliable visual capture. Turn on normal room lighting while scanning — it can be dimmed again afterward.",
                    systemImage: "lightbulb"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.yellow)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            }

            if let statusMessage,
               !statusMessage.isEmpty
            {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .accessibilityLabel(
                        String(localized: "Capture status")
                    )
                    .accessibilityValue(statusMessage)
            }

            mobilityControl

            compactEvidenceSummary
                .font(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private var mobilityControl: some View {
        switch guidanceProgress.movementCapability {
        case .stationaryOnly:
            HStack(spacing: 8) {
                Label(
                    "Scanning from this position",
                    systemImage: "figure.stand"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.cyan)

                Spacer(minLength: 6)

                Button("Allow movement") {
                    setMovementCapability(.unrestricted)
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        case .safetyConstrained:
            // #313: movement was marked unsafe — translation prompts
            // are hidden and the mode is labeled distinctly from a
            // voluntary stationary scan so Review can tell them apart.
            HStack(spacing: 8) {
                Label(
                    "Movement marked unsafe — staying put",
                    systemImage: "hand.raised.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

                Spacer(minLength: 6)

                Button("Safe to move") {
                    setMovementCapability(.unrestricted)
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        case .unrestricted:
            // #313: while guidance may instruct movement, both
            // opt-outs stay immediately visible — "I cannot move"
            // (operator preference) and "Movement unsafe here"
            // (environment). Neither is framed as failing the scan.
            if motionGuidance.map({
                $0.action.requiresPhysicalTranslation
            }) == true {
                HStack(spacing: 8) {
                    Button {
                        setMovementCapability(.stationaryOnly)
                    } label: {
                        Label(
                            "I cannot move around this area",
                            systemImage: "figure.stand"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        setMovementCapability(.safetyConstrained)
                    } label: {
                        Label(
                            "Movement unsafe here",
                            systemImage: "hand.raised"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .controlSize(.small)
                }
            }
        }
    }

    private var compactBottomControls: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button(action: captureEvidenceFrame) {
                Label(
                    isCapturingEvidence
                        ? "Saving…"
                        : "Save evidence",
                    systemImage: "camera.fill"
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isEndingScan || isCapturingEvidence)
            .accessibilityLabel(
                String(localized: "Save evidence frame")
            )

            // #325: one large tap marks the current view for mandatory
            // Review without interrupting the scan. The optional
            // details sheet is offered only once the flag persisted.
            Button {
                if let flagID = flagForReview() {
                    flagDetailsID = flagID
                    flagDetailsCategory = nil
                    flagDetailsNote = ""
                }
            } label: {
                Label(
                    revisitFlagsFull
                        ? "Flags full"
                        : revisitFlagCount > 0
                        ? String(
                            format: String(
                                localized: "Flag (%d)"
                            ),
                            revisitFlagCount
                        )
                        : String(localized: "Flag"),
                    systemImage: "flag.fill"
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(minHeight: 38)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isEndingScan || revisitFlagsFull)
            .accessibilityLabel(
                String(localized: "Flag area for review")
            )
            .accessibilityHint(
                String(
                    localized:
                        "Marks the current view for mandatory review without interrupting the scan."
                )
            )

            Spacer(minLength: 8)

            Button(action: requestEndScan) {
                Label(
                    isEndingScan
                        ? "Finishing…"
                        : "End",
                    systemImage: "checkmark.circle.fill"
                )
                .lineLimit(1)
                .minimumScaleFactor(0.80)
                .frame(minHeight: 38)
            }
            .buttonStyle(.bordered)
            .tint(
                endScanGuidance != nil
                ? .orange
                : (primaryScanReadyToEnd ? .green : nil)
            )
            .controlSize(.regular)
            .disabled(isEndingScan)
            .accessibilityLabel(
                String(localized: "End scan")
            )
        }
    }

    /// Explicit busy state for the End transaction (#279): the
    /// controls are disabled and this overlay explains that RoomPlan
    /// is producing the final result, so the operator can distinguish
    /// "still scanning" from "committing End".
    private var finishingCaptureOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("Finishing capture…")
                .font(.headline.weight(.semibold))
            Text(
                "RoomPlan is producing the final result. The scan data stays recoverable until it finishes."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
        }
        .padding(20)
        .frame(maxWidth: 300)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(localized: "Finishing capture")
        )
    }

    private var compactEvidenceSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                spatialSummaryButton

                if derivedPreview.hasEvidence {
                    Divider()
                        .frame(height: 16)
                    derivedSummaryButton
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                spatialSummaryButton

                if derivedPreview.hasEvidence {
                    derivedSummaryButton
                }
            }
        }
        .font(.caption)
    }

    private var spatialSummaryButton: some View {
        Button {
            withAnimation(
                .easeInOut(duration: 0.20)
            ) {
                isHUDExpanded = true
                showingSpatialMap = true
            }
        } label: {
            HStack(spacing: 5) {
                Text(spatialObservationTitle)
                    .fontWeight(.semibold)
                Text(spatialCoverageCounts)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
        .buttonStyle(.plain)
    }

    private var derivedSummaryButton: some View {
        Button {
            withAnimation(
                .easeInOut(duration: 0.20)
            ) {
                isHUDExpanded = true
                showingDerivedPreview = true
            }
        } label: {
            HStack(spacing: 6) {
                Label(
                    String(
                        format: String(
                            localized: "Observed shape: %@"
                        ),
                        primaryDerivedShapeLabel
                    ),
                    systemImage: "viewfinder.circle"
                )
                .fontWeight(.semibold)

                Text("Tap for details")
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Color.orange.opacity(0.16),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func expandedHUD(
        maxHeight: CGFloat
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                expandedStatusRow
                directionCoverageSection

                DisclosureGroup(
                    isExpanded: $showingSpatialMap
                ) {
                    VStack(spacing: 8) {
                        SpatialCoverageMapView(
                            summary: spatialCoverage
                        )
                        .frame(height: 116)

                        HStack(spacing: 10) {
                            spatialLegend(
                                "Observed",
                                color: .green
                            )
                            spatialLegend(
                                "Weak",
                                color: .orange
                            )
                            spatialLegend(
                                "Unknown",
                                color: .gray
                            )
                        }
                        .font(.caption2)

                        if spatialCoverage.usesDepthFallback {
                            Label(
                                "Scene-depth fallback active",
                                systemImage: "viewfinder"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.cyan)
                        }

                        verticalCoverageStrip
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        Text(spatialObservationTitle)
                            .font(
                                .subheadline
                                    .weight(.semibold)
                            )
                        Spacer()
                        Text(spatialCoverageCounts)
                            .font(
                                .caption
                                    .monospacedDigit()
                            )
                            .foregroundStyle(.secondary)
                    }
                }

                if derivedPreview.hasEvidence {
                    DisclosureGroup(
                        isExpanded: $showingDerivedPreview
                    ) {
                        DerivedShapePreviewPanel(
                            snapshot: derivedPreview,
                            mode: $derivedPreviewMode
                        )
                        .padding(.top, 6)
                    } label: {
                        HStack {
                            Text("Observed shape")
                                .font(
                                    .subheadline
                                        .weight(.semibold)
                                )
                            Spacer()
                            Text(primaryDerivedShapeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                objectPassSection
                declaredRegionsSection
                loopClosureSection
                guidanceCuesToggle

                Button {
                    showingAuthorityHelp = true
                } label: {
                    Label(
                        "Details",
                        systemImage: "info.circle"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
        .frame(maxHeight: maxHeight)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    private var expandedStatusRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    String(
                        format: String(localized: "Observation: %@"),
                        observationStateLabel
                    )
                )
                .font(.caption.weight(.semibold))

                HStack(spacing: 10) {
                    Label(
                        meshAvailabilityLabel,
                        systemImage: meshAvailabilitySystemImage
                    )
                    Label(
                        String(
                            format: String(localized: "Evidence %d"),
                            evidenceFrameCount
                        ),
                        systemImage: "camera"
                    )
                    if automaticEvidenceCount > 0 {
                        Label(
                            String(
                                format: String(
                                    localized: "Auto %d"
                                ),
                                automaticEvidenceCount
                            ),
                            systemImage: "camera.badge.clock"
                        )
                    }
                    if coverage.latestHasSceneDepth {
                        Label(
                            String(localized: "Depth"),
                            systemImage: "viewfinder"
                        )
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let meshDiagnosticText {
                    Text(meshDiagnosticText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text("Next direction")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                RelativeGuidanceCompass(
                    coverage: coverage
                )
                .frame(width: 58, height: 58)
            }
        }
    }

    private var directionCoverageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Direction coverage")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Advisory")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 3) {
                ForEach(
                    0..<coverage.sectorCount,
                    id: \.self
                ) { sectorIndex in
                    VStack(spacing: 2) {
                        coverageCell(
                            sectorIndex: sectorIndex,
                            band: .high
                        )
                        coverageCell(
                            sectorIndex: sectorIndex,
                            band: .level
                        )
                        coverageCell(
                            sectorIndex: sectorIndex,
                            band: .low
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 36)

            HStack {
                Text("← Look left")
                Spacer()
                Text("Start direction")
                Spacer()
                Text("Look right →")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var actionSentence: String {
        if let endScanGuidance {
            return endScanGuidance
        }

        if scanGuidanceComplete {
            return String(
                localized:
                    "Scan guidance complete. You can end now or continue for more detail."
            )
        }

        if let motionGuidance {
            let prompt = ScanMotionGuidanceCopy.prompt(
                for: motionGuidance,
                language:
                    ScanMotionGuidanceCopy.preferredLanguage
            )
            if primaryScanReadyToEnd {
                return String(
                    format: String(
                        localized:
                            "Base scan complete. Optional extra observation: %@"
                    ),
                    prompt
                )
            }
            return prompt
        }

        if guidanceProgress.movementCapability == .unrestricted,
           coverage.latestTrackingState == .normal,
           observation.recheckSuggested
        {
            return String(
                localized:
                    "Show this area again from another angle."
            )
        }

        return guidanceText
    }

    private var authorityHelpView: some View {
        NavigationStack {
            List {
                Section("RoomPlan approximation") {
                    Text(
                        "RoomPlan lines are a live structural approximation. HTDT observation evidence is collected separately."
                    )
                }

                Section("Direction coverage") {
                    Text(
                        "Direction coverage is trajectory guidance only and does not prove geometric completeness."
                    )
                }

                Section("Movement guidance") {
                    Text(
                        "If the room layout prevents you from walking around a target, choose I cannot move around this area. HTDT will stop requiring translation/orbit guidance for this scan; weak and unknown spatial cells remain advisory."
                    )
                    Text(
                        ScanMotionGuidanceCopy.safetyDisclaimer(
                            language:
                                ScanMotionGuidanceCopy
                                .preferredLanguage
                        )
                    )
                    Text(
                        "Movement prompts are advisory: they never claim the path behind you was checked, and they never require walking backward. When movement is not safe, choose Movement unsafe here to hide translation prompts without failing the scan."
                    )
                }

                Section("Vertical coverage") {
                    Text(
                        "Coverage cells are tracked by height too, so a floor-level observation does not count as covering the ceiling at the same spot. Weak upper or lower bands stay visible in the Details HUD and at the end-of-scan review."
                    )
                }

                Section("Spatial observation") {
                    Text(
                        "Unknown means no observation authority; it is not a missing wall or surface."
                    )
                }

                Section("Observed shape") {
                    Text(
                        "The views are separate evidence representations; neither is promoted as canonical geometry here."
                    )
                }
            }
            .font(.callout)
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Close") {
                        showingAuthorityHelp = false
                    }
                }
            }
        }
    }

    private var recheckBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(
                String(localized: "Recheck shape"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))

            Text(
                String(
                    localized:
                        "Supporting observation is still weak; follow the current guidance."
                )
            )
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            .thinMaterial,
            in: RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
        .accessibilityHint(
            String(
                localized:
                    "Supporting HTDT depth or mesh observation is still weak for this repeatedly viewed area."
            )
        )
    }

    private var observationStateLabel: String {
        switch observation.state {
        case .provisional:
            return String(localized: "Provisional")
        case .accumulating:
            return String(localized: "Accumulating")
        case .wellObserved:
            return String(localized: "Well observed")
        }
    }

    private func coverageCell(
        sectorIndex: Int,
        band: ScanCoveragePitchBand
    ) -> some View {
        let observed = coverage.isObserved(
            sectorIndex: sectorIndex,
            pitchBand: band
        )
        let isTarget =
            coverage.recommendedGap
            == ScanCoverageGap(
                sectorIndex: sectorIndex,
                pitchBand: band
            )

        return RoundedRectangle(cornerRadius: 2)
            .fill(
                observed
                ? Color.green.opacity(0.9)
                : Color.red.opacity(0.45)
            )
            .overlay {
                if observed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        isTarget ? Color.yellow : Color.clear,
                        lineWidth: isTarget ? 2 : 0
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isTarget {
                    Image(systemName: "scope")
                        .font(.system(size: 6, weight: .black))
                        .foregroundStyle(.yellow)
                        .offset(x: 2, y: -2)
                }
            }
            .accessibilityLabel(
                isTarget
                ? String(localized: "Next direction")
                : String(localized: "Look-around coverage")
            )
    }

    @ViewBuilder
    private func spatialLegend(
        _ label: LocalizedStringKey,
        color: Color
    ) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
        }
    }

    private var spatialObservationTitle: String {
        spatialCoverage.usesDepthFallback
            ? String(localized: "Spatial observation · depth")
            : String(localized: "Spatial observation")
    }

    private var spatialCoverageCounts: String {
        String(
            format: String(localized: "%d observed · %d weak"),
            spatialCoverage.observedRegionCount,
            spatialCoverage.weakRegionCount
        )
    }

    /// #329: the five display bands of the 3D coverage layer — one
    /// chip per stratum from lowest to highest, colored by the weakest
    /// voxel classification in that band so a ceiling gap is visible
    /// even when the floor cells below it are fully observed.
    @ViewBuilder
    private var verticalCoverageStrip: some View {
        let vertical = spatialCoverage.vertical
        if vertical.voxelCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Height bands")
                        .font(.caption2.weight(.semibold))
                    Spacer()
                    Text(
                        String(
                            format: String(
                                localized: "%d weak heights"
                            ),
                            vertical.weakVoxelCount
                        )
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(
                        vertical.weakVoxelCount > 0
                        ? Color.orange
                        : Color.secondary
                    )
                }

                HStack(spacing: 3) {
                    ForEach(
                        vertical.displayBands,
                        id: \.band
                    ) { bandSummary in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                bandColor(bandSummary)
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("Floor")
                    Spacer()
                    Text("Ceiling")
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                String(
                    format: String(
                        localized: "Vertical coverage: %d cells, %d weak"
                    ),
                    vertical.voxelCount,
                    vertical.weakVoxelCount
                )
            )
        }
    }

    private func bandColor(
        _ band: SpatialVerticalBandSummary
    ) -> Color {
        if band.voxelCount == 0 {
            return .gray.opacity(0.25)
        }
        if band.weakCount > 0 {
            return .orange.opacity(0.75)
        }
        return .green.opacity(0.8)
    }

    private var primaryDerivedShapeLabel: String {
        if let decomposition = derivedPreview.objectDecomposition,
           decomposition.components.count > 1
        {
            if let selected =
                derivedPreview.objectProxies
                    .compactMap(\.selected)
                    .first
            {
                // The compact HUD reports the best resolved observed shape.
                // Component/candidate count remains available in Details so
                // a resolved circle/ellipse is not visually presented as
                // unresolved just because several bounded components exist.
                return shapeKindLabel(selected.kind)
            }

            return String(
                format: String(localized: "Observed shape candidates %d"),
                decomposition.components.count
            )
        }

        if let support = derivedPreview.supportAnalysis {
            switch support.resolution {
            case .separatedSupports:
                return String(
                    format: String(localized: "%d observed supports"),
                    support.supports.count
                )
            case .floatingBodyUnresolved:
                return String(localized: "Lower support unresolved")
            case .solidToFloor, .insufficientHeightEvidence:
                break
            }
        }

        if let proxy = derivedPreview.objectProxies.first {
            guard let selected = proxy.selected else {
                switch proxy.resolution {
                case .resolved:
                    return String(localized: "Shape unresolved")
                case .insufficientEvidence:
                    return String(localized: "Shape unresolved")
                case .ambiguousEvidence:
                    return String(localized: "Shape ambiguous")
                }
            }

            return shapeKindLabel(selected.kind)
        }

        if derivedPreview.wallChain != nil {
            return String(localized: "Observed wall chain")
        }

        return String(localized: "No bounded shape evidence yet")
    }

    private var primaryScanReadyToEnd: Bool {
        coverage.latestTrackingState == .normal
            && coverage.coverageFraction >= 0.95
            && coverage.pitchBandCoverageFraction(.low) >= 0.75
            && coverage.pitchBandCoverageFraction(.high) >= 0.75
    }

    private var scanGuidanceComplete: Bool {
        guidanceProgress.isComplete
    }

    private func shapeKindLabel(
        _ kind: DerivedShapeKind
    ) -> String {
        switch kind {
        case .orientedRectangle:
            return String(localized: "Oriented rectangle")
        case .circle:
            return String(localized: "Circle")
        case .ellipse:
            return String(localized: "Ellipse")
        case .polygon:
            return String(localized: "Polygon")
        }
    }

    private var meshAvailabilityLabel: String {
        switch spatialCoverage.meshAvailability.state {
        case .unavailable:
            return String(localized: "Mesh unavailable")
        case .enabledNoAnchors:
            return String(localized: "Mesh enabled · no anchors yet")
        case .anchorsObserved:
            return String(
                format: String(localized: "Mesh anchors %d"),
                spatialCoverage.meshAvailability.activeMeshAnchorCount
            )
        }
    }

    private var meshAvailabilitySystemImage: String {
        switch spatialCoverage.meshAvailability.state {
        case .unavailable:
            return "square.slash"
        case .enabledNoAnchors:
            return "square.3.layers.3d"
        case .anchorsObserved:
            return "square.3.layers.3d.top.filled"
        }
    }

    private var meshDiagnosticText: String? {
        let diagnostic = spatialCoverage.meshAvailability

        if diagnostic.configurationMismatchSuspected {
            let configuration =
                diagnostic.activeConfigurationName
                ?? String(localized: "Unknown configuration")
            return String(
                format: String(
                    localized:
                        "Active AR configuration (%@) has scene reconstruction disabled. RoomPlan may have changed the session configuration; spatial coverage will not silently fall back."
                ),
                configuration
            )
        }

        switch diagnostic.state {
        case .enabledNoAnchors:
            return String(
                localized:
                    "Scene reconstruction is enabled, but no ARMesh anchors have been observed yet."
            )
        case .unavailable:
            return String(
                localized:
                    "ARMesh evidence is unavailable in the active session. Direction coverage remains separate."
            )
        case .anchorsObserved:
            return nil
        }
    }

    // MARK: - Targeted object pass (#250)

    /// Optional "Scan this object" surface: a bounded anchored orbit
    /// pass with target-specific guidance and explicit
    /// Accept/Retake/Cancel. Never implies a segmented model.
    @ViewBuilder
    private var objectPassSection: some View {
        if let status = targetScanStatus {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(
                        "Scanning this object",
                        systemImage: "viewfinder"
                    )
                    .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(
                        String(
                            format: String(localized: "%d / %d angles"),
                            status.observedBucketCount,
                            status.totalBucketCount
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                ProgressView(
                    value: status.angularCoverageFraction
                )
                .tint(status.isComplete ? .green : .accentColor)

                Text(targetGuidanceText(status))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Accept") { acceptTargetScan() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!status.isComplete)
                    Button("Retake") { retakeTargetScan() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Cancel", role: .cancel) {
                        cancelTargetScan()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 6)
        } else {
            Button {
                beginTargetScan()
            } label: {
                Label(
                    "Scan this object",
                    systemImage: "scope"
                )
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isEndingScan)
            .padding(.top, 6)
        }
    }

    private func targetGuidanceText(
        _ status: TargetScanStatus
    ) -> String {
        if status.outOfRange {
            return String(
                localized:
                    "You have drifted too far from the object; move back toward it."
            )
        }
        if status.expired {
            return String(
                localized:
                    "The object pass timed out. Accept or retake to finish it."
            )
        }
        switch status.guidance {
        case .hold:
            return String(
                localized:
                    "Hold steady on the object until this angle is recorded."
            )
        case .approach:
            return String(
                localized: "Move closer to the object."
            )
        case .retreat:
            return String(
                localized: "Step back so the whole object stays in view."
            )
        case .orbit(let clockwise):
            return clockwise
                ? String(
                    localized:
                        "Orbit clockwise around the object to cover new angles."
                )
                : String(
                    localized:
                        "Orbit counter-clockwise around the object to cover new angles."
                )
        }
    }

    // MARK: - Operator-declared regions (#257)

    /// Declare a bounded unresolved coverage cell as intentionally
    /// left (inaccessible/occluded/unsafe/out-of-scope); reversible
    /// until finalization, never reported as observed.
    @ViewBuilder
    private var declaredRegionsSection: some View {
        Menu {
            ForEach(DeclaredRegionReason.allCases, id: \.self) {
                reason in
                Button(declaredReasonLabel(reason)) {
                    declareNearestUnresolvedRegion(reason)
                }
            }
        } label: {
            Label(
                "Mark nearest unresolved area…",
                systemImage: "exclusionzone"
            )
            .font(.caption.weight(.semibold))
        }
        .disabled(isEndingScan)

        ForEach(declaredRegions, id: \.key) { region in
            HStack(spacing: 8) {
                Text(declaredReasonLabel(region.reason))
                    .font(.caption2)
                Spacer()
                Button(String(localized: "Revoke")) {
                    revokeOperatorRegion(region.key)
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isEndingScan)
            }
        }
        if !declaredRegions.isEmpty {
            Text(
                "Marked areas stay unresolved on purpose; guidance no longer requests them."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func declaredReasonLabel(
        _ reason: DeclaredRegionReason
    ) -> String {
        switch reason {
        case .inaccessible:
            return String(localized: "Cannot reach")
        case .occludedFixedObject:
            return String(localized: "Blocked by fixed object")
        case .unsafe:
            return String(localized: "Unsafe to approach")
        case .outOfScope:
            return String(localized: "Out of scope")
        }
    }

    // MARK: - Return-to-start check (#273)

    /// Optional advisory loop-closure check: arm it, walk back to the
    /// scan start, and compare the residual. Never silently corrects
    /// coordinates.
    @ViewBuilder
    private var loopClosureSection: some View {
        Toggle(
            isOn: Binding(
                get: { loopClosureCheckActive },
                set: { setLoopClosureCheckActive($0) }
            )
        ) {
            Label(
                "Return-to-start check",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(.caption.weight(.semibold))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(isEndingScan)

        if loopClosureCheckActive {
            if let assessment = loopClosureAssessment {
                Text(loopClosureAssessmentText(assessment))
                    .font(.caption2)
                    .foregroundStyle(
                        assessment.verdict == .inconsistent
                            ? .orange
                            : .secondary
                    )
            } else {
                Text(
                    "Walk back to where the scan started; a consistency result appears here."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func loopClosureAssessmentText(
        _ assessment: LoopClosureAssessment
    ) -> String {
        switch assessment.verdict {
        case .closed:
            return String(
                localized:
                    "Start region reached and the loop closed within tolerance."
            )
        case .inconsistent:
            return String(
                localized:
                    "Back at the start, but the current pose disagrees with the start reference. Consider re-observing or rescanning."
            )
        case .notAtStart:
            return String(
                localized:
                    "Move back toward the scan start to complete the check."
            )
        case .unavailable:
            return String(
                localized:
                    "Check unavailable: no start reference or tracking is not stable enough."
            )
        }
    }

    // MARK: - Non-visual cues (#252)

    private var guidanceCuesToggle: some View {
        Toggle(
            isOn: Binding(
                get: { guidanceCuesEnabled },
                set: { setGuidanceCuesEnabled($0) }
            )
        ) {
            Label(
                "Haptic & spoken cues",
                systemImage: "waveform"
            )
            .font(.caption.weight(.semibold))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func requestEndScan() {
        if shouldReviewCoverageBeforeEnding {
            showingEndScanReview = true
        } else {
            endScan()
        }
    }

    private var shouldReviewCoverageBeforeEnding: Bool {
        if scanGuidanceComplete {
            return false
        }

        // Spatial weak/unknown cells are advisory. Once the operator has
        // completed broad directional capture under normal tracking, pressing
        // End must not be turned into another effectively mandatory spatial
        // loop.
        if primaryScanReadyToEnd {
            return false
        }

        return coverage.coverageFraction < 0.75
            || coverage.pitchBandCoverageFraction(.low) < 0.50
            || coverage.pitchBandCoverageFraction(.high) < 0.50
    }

    private var coveragePercent: Int {
        Int((coverage.coverageFraction * 100).rounded())
    }

    private var trackingLabel: String {
        switch coverage.latestTrackingState {
        case .normal:
            return String(localized: "Tracking normal")
        case .limited:
            return String(localized: "Tracking limited")
        case .unavailable:
            return String(localized: "Tracking unavailable")
        case nil:
            return String(localized: "Starting tracking…")
        }
    }

    private var trackingSystemImage: String {
        switch coverage.latestTrackingState {
        case .normal:
            return "location.fill"
        case .limited:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "xmark.octagon.fill"
        case nil:
            return "location"
        }
    }

    private var guidanceText: String {
        switch coverage.latestTrackingState {
        case .unavailable:
            return String(
                localized: "Tracking is unavailable. Hold the phone steady and point it at previously seen room features."
            )
        case .limited:
            return limitedTrackingGuidance
        case .normal, nil:
            break
        }

        if let motionGuidance {
            return ScanMotionGuidanceCopy.prompt(
                for: motionGuidance,
                language:
                    ScanMotionGuidanceCopy.preferredLanguage
            )
        }

        if let guidance = coverage.recommendedGuidance {
            return currentRelativeGuidanceText(guidance)
        }

        if coverage.referenceYawRadians == nil {
            return String(
                localized: "Move slowly and scan the whole room from different heights and angles."
            )
        }

        return String(
            localized: "Broad look-around coverage reached. Check the RoomPlan overlay for unrecognized surfaces before ending."
        )
    }

    private func currentRelativeGuidanceText(
        _ guidance: ScanCoverageGuidance
    ) -> String {
        switch guidance.arrow {
        case .aligned:
            return String(
                localized: "Slowly scan this direction."
            )
        case .left:
            return String(localized: "Turn left.")
        case .right:
            return String(localized: "Turn right.")
        case .up:
            return String(
                localized: "Capture the upper area."
            )
        case .down:
            return String(
                localized: "Capture the lower area."
            )
        case .upLeft:
            return combinedGuidance(
                horizontal: String(localized: "Turn left."),
                vertical: String(
                    localized: "Capture the upper area."
                )
            )
        case .upRight:
            return combinedGuidance(
                horizontal: String(localized: "Turn right."),
                vertical: String(
                    localized: "Capture the upper area."
                )
            )
        case .downLeft:
            return combinedGuidance(
                horizontal: String(localized: "Turn left."),
                vertical: String(
                    localized: "Capture the lower area."
                )
            )
        case .downRight:
            return combinedGuidance(
                horizontal: String(localized: "Turn right."),
                vertical: String(
                    localized: "Capture the lower area."
                )
            )
        }
    }

    private func combinedGuidance(
        horizontal: String,
        vertical: String
    ) -> String {
        String(
            format: String(localized: "Guidance %@ %@"),
            horizontal,
            vertical
        )
    }

    private func motionGuidanceOverlay(
        _ guidance: ScanMotionGuidance
    ) -> some View {
        VStack(spacing: 6) {
            Text(motionGuidanceSymbol(guidance))
                .font(
                    .system(
                        size: 54,
                        weight: .heavy,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)
                .shadow(radius: 4)

            Text(
                ScanMotionGuidanceCopy.category(
                    for: guidance.action,
                    language:
                        ScanMotionGuidanceCopy.preferredLanguage
                )
            )
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ScanMotionGuidanceCopy.prompt(
                for: guidance,
                language:
                    ScanMotionGuidanceCopy.preferredLanguage
            )
        )
    }

    private func motionGuidanceSymbol(
        _ guidance: ScanMotionGuidance
    ) -> String {
        switch guidance.action {
        case .trackingRecovery:
            return "!"
        case .rotate:
            return guidance.horizontalDirection == .left
                ? "↺"
                : "↻"
        case .tilt:
            return guidance.verticalDirection == .down
                ? "↓"
                : "↑"
        case .translate:
            switch guidance.translationDirection ?? .right {
            case .left:
                return "⇠"
            case .right:
                return "⇢"
            case .forward:
                return "⇡"
            case .backward:
                return "⇣"
            }
        case .approach:
            return "⇡"
        case .retreat:
            return "⇣"
        case .orbit:
            return guidance.horizontalDirection == .left
                ? "◌↺"
                : "↻◌"
        case .reobserveAnotherAngle:
            return "◌"
        case .holdObserve:
            return "◎"
        }
    }

    private func directionArrowOverlay(
        _ guidance: ScanCoverageGuidance
    ) -> some View {
        VStack(spacing: 6) {
            Text(arrowSymbol(guidance.arrow))
                .font(
                    .system(
                        size: 54,
                        weight: .heavy,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)
                .shadow(radius: 4)

            Text(
                guidance.arrow == .aligned
                ? String(localized: "Slowly scan this direction.")
                : String(localized: "Next direction")
            )
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            currentRelativeGuidanceText(guidance)
        )
    }

    private func arrowSymbol(
        _ arrow: ScanGuidanceArrow
    ) -> String {
        switch arrow {
        case .left:
            return "←"
        case .right:
            return "→"
        case .up:
            return "↑"
        case .down:
            return "↓"
        case .upLeft:
            return "↖"
        case .upRight:
            return "↗"
        case .downLeft:
            return "↙"
        case .downRight:
            return "↘"
        case .aligned:
            return "◎"
        }
    }

    private var limitedTrackingGuidance: String {
        switch coverage.latestTrackingReason {
        case "excessive_motion":
            return String(
                localized: "Move more slowly so AR tracking can recover."
            )
        case "insufficient_features":
            return String(
                localized: "Point at a textured wall, corner, or furniture edge to recover tracking."
            )
        case "relocalizing":
            return String(
                localized: "Point at previously scanned room features while relocalizing."
            )
        case "initializing":
            return String(
                localized: "Hold the phone steady while AR tracking initializes."
            )
        default:
            return String(
                localized: "Tracking is limited. Move slowly and keep previously scanned features in view."
            )
        }
    }

    private func pitchBandLabel(
        _ band: ScanCoveragePitchBand
    ) -> String {
        switch band {
        case .low:
            return String(localized: "Low")
        case .level:
            return String(localized: "Level")
        case .high:
            return String(localized: "High")
        }
    }

    private func relativeDirectionLabel(
        sectorIndex: Int
    ) -> String {
        let normalized =
            ((sectorIndex % coverage.sectorCount)
             + coverage.sectorCount)
            % coverage.sectorCount

        switch normalized {
        case 0:
            return String(localized: "Front")
        case 1, 2:
            return String(localized: "Front right")
        case 3:
            return String(localized: "Right")
        case 4, 5:
            return String(localized: "Rear right")
        case 6:
            return String(localized: "Rear")
        case 7, 8:
            return String(localized: "Rear left")
        case 9:
            return String(localized: "Left")
        default:
            return String(localized: "Front left")
        }
    }
}


private struct RelativeGuidanceCompass: View {
    let coverage: ScanCoverageSummary

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(
                geometry.size.width,
                geometry.size.height
            )
            let radius = diameter * 0.38
            let needleLength = radius * 0.82

            ZStack {
                Circle()
                    .stroke(
                        Color.white.opacity(0.28),
                        lineWidth: 1
                    )

                compassNeedle(
                    angleRadians: 0,
                    length: needleLength,
                    width: 1,
                    color: .secondary
                )
                compassMarker(
                    systemImage: "flag.fill",
                    angleRadians: 0,
                    radius: radius,
                    color: .secondary,
                    accessibilityLabel:
                        String(localized: "Start direction")
                )

                if let targetYaw =
                    coverage.recommendedGuidance?
                        .targetYawRadians
                {
                    compassNeedle(
                        angleRadians: targetYaw,
                        length: needleLength,
                        width: 2,
                        color: .yellow
                    )
                    compassMarker(
                        systemImage: "scope",
                        angleRadians: targetYaw,
                        radius: radius,
                        color: .yellow,
                        accessibilityLabel:
                            String(localized: "Next direction")
                    )
                }

                if let currentYaw =
                    coverage.currentRelativeYawRadians
                {
                    compassNeedle(
                        angleRadians: currentYaw,
                        length: needleLength,
                        width: 2,
                        color: .white
                    )
                    compassMarker(
                        systemImage: "location.north.fill",
                        angleRadians: currentYaw,
                        radius: radius,
                        color: .white,
                        accessibilityLabel:
                            String(localized: "Current direction")
                    )
                }

                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 4, height: 4)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func compassNeedle(
        angleRadians: Double,
        length: CGFloat,
        width: CGFloat,
        color: Color
    ) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.radians(angleRadians))
    }

    private func compassMarker(
        systemImage: String,
        angleRadians: Double,
        radius: CGFloat,
        color: Color,
        accessibilityLabel: String
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .offset(
                x: CGFloat(sin(angleRadians)) * radius,
                y: -CGFloat(cos(angleRadians)) * radius
            )
            .accessibilityLabel(accessibilityLabel)
    }
}


private struct ScanCoverageEndReview: View {
    let coverage: ScanCoverageSummary
    let spatialCoverage: SpatialScanCoverageSummary
    let continueScanning: () -> Void
    let endAnyway: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(
                        "Direction coverage",
                        value: percent(coverage.coverageFraction)
                    )
                    LabeledContent(
                        "Lower room",
                        value: percent(
                            coverage.pitchBandCoverageFraction(.low)
                        )
                    )
                    LabeledContent(
                        "Level view",
                        value: percent(
                            coverage.pitchBandCoverageFraction(.level)
                        )
                    )
                    LabeledContent(
                        "Upper room",
                        value: percent(
                            coverage.pitchBandCoverageFraction(.high)
                        )
                    )
                } header: {
                    Text("Direction coverage")
                } footer: {
                    Text(
                        "This is a trajectory-based guide, not a geometric completeness measurement."
                    )
                }

                Section {
                    LabeledContent(
                        "Mesh availability",
                        value: meshAvailabilityReviewLabel
                    )
                    LabeledContent(
                        "Observed regions",
                        value: String(spatialCoverage.observedRegionCount)
                    )
                    LabeledContent(
                        "Weak regions",
                        value: String(spatialCoverage.weakRegionCount)
                    )
                    LabeledContent(
                        "Unknown map cells",
                        value: String(
                            spatialCoverage.displayUnknownRegionCount
                        )
                    )

                    // #329: the vertical layer is listed separately so
                    // a floor-level "observed" classification can never
                    // hide an unobserved ceiling at the same X/Z.
                    if spatialCoverage.vertical.voxelCount > 0 {
                        LabeledContent(
                            "Vertical cells",
                            value: String(
                                format: String(
                                    localized: "%d total · %d weak"
                                ),
                                spatialCoverage.vertical.voxelCount,
                                spatialCoverage.vertical
                                    .weakVoxelCount
                            )
                        )

                        ForEach(
                            spatialCoverage.vertical.displayBands,
                            id: \.band
                        ) { band in
                            if band.voxelCount > 0 {
                                LabeledContent(
                                    verticalBandLabel(band.band),
                                    value: String(
                                        format: String(
                                            localized:
                                                "%d observed · %d weak"
                                        ),
                                        band.observedCount,
                                        band.weakCount
                                    )
                                )
                            }
                        }
                    }

                    if !weakSpatialLabels.isEmpty {
                        Text(
                            String(
                                format: String(localized: "Weak: %@"),
                                weakSpatialLabels
                                    .prefix(4)
                                    .joined(separator: " · ")
                            )
                        )
                        .font(.caption)
                    }

                    if !unknownSpatialLabels.isEmpty {
                        Text(
                            String(
                                format: String(localized: "Unknown: %@"),
                                unknownSpatialLabels
                                    .prefix(4)
                                    .joined(separator: " · ")
                            )
                        )
                        .font(.caption)
                    }
                } header: {
                    Text("Spatial coverage")
                } footer: {
                    Text(
                        "Spatial coverage is advisory. Unknown means no observation authority, not a missing wall, and it is never a finalization gate."
                    )
                }

                if !gapSectors.isEmpty {
                    Section("Most under-observed directions") {
                        ForEach(
                            Array(gapSectors.prefix(4)),
                            id: \.self
                        ) { sectorIndex in
                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                HStack {
                                    Text(
                                        directionLabel(sectorIndex)
                                    )
                                    Spacer()
                                    Text(
                                        String(
                                            format: String(
                                                localized:
                                                    "%d of 3 angles"
                                            ),
                                            coverage
                                                .observedPitchBandCount(
                                                    sectorIndex:
                                                        sectorIndex
                                                )
                                        )
                                    )
                                    .foregroundStyle(.secondary)
                                }

                                Text(
                                    String(
                                        format: String(
                                            localized: "Missing: %@"
                                        ),
                                        missingBandLabels(
                                            sectorIndex
                                        )
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button(action: continueScanning) {
                        Label(
                            "Continue scanning",
                            systemImage: "camera.viewfinder"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(
                        role: .destructive,
                        action: endAnyway
                    ) {
                        Label(
                            "End anyway",
                            systemImage: "checkmark.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text(
                        "Ending is always allowed because advisory coverage is not a canonical finalization gate."
                    )
                }
            }
            .navigationTitle("Review scan coverage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        continueScanning()
                    }
                }
            }
        }
    }

    private var meshAvailabilityReviewLabel: String {
        switch spatialCoverage.meshAvailability.state {
        case .unavailable:
            return String(localized: "Unavailable")
        case .enabledNoAnchors:
            return String(localized: "Enabled, no anchors yet")
        case .anchorsObserved:
            return String(
                format: String(localized: "%d anchors observed"),
                spatialCoverage.meshAvailability.activeMeshAnchorCount
            )
        }
    }

    private var weakSpatialLabels: [String] {
        spatialLabels(for: .weak)
    }

    private var unknownSpatialLabels: [String] {
        spatialLabels(for: .unknown)
    }

    private func spatialLabels(
        for classification: SpatialCoverageClassification
    ) -> [String] {
        guard let bounds = spatialCoverage.displayBounds else {
            return []
        }

        var labels: Set<String> = []
        for z in bounds.minZ...bounds.maxZ {
            for x in bounds.minX...bounds.maxX {
                let key = SpatialCoverageCellKey(x: x, z: z)
                guard spatialCoverage.classification(at: key)
                        == classification
                else {
                    continue
                }
                labels.insert(spatialRegionLabel(key))
            }
        }
        return labels.sorted()
    }

    private func spatialRegionLabel(
        _ key: SpatialCoverageCellKey
    ) -> String {
        let x =
            (Double(key.x) + 0.5)
            * spatialCoverage.cellSizeMeters
        let z =
            (Double(key.z) + 0.5)
            * spatialCoverage.cellSizeMeters
        let angle = atan2(x, z)
        let fullTurn = 2 * Double.pi
        let shifted =
            (angle + Double.pi / 8)
                .truncatingRemainder(dividingBy: fullTurn)
        let positive =
            shifted >= 0
            ? shifted
            : shifted + fullTurn
        let sector = Int(
            floor(positive / (Double.pi / 4))
        ) % 8

        let direction: String
        switch sector {
        case 0:
            direction = String(localized: "Front")
        case 1:
            direction = String(localized: "Front right")
        case 2:
            direction = String(localized: "Right")
        case 3:
            direction = String(localized: "Rear right")
        case 4:
            direction = String(localized: "Rear")
        case 5:
            direction = String(localized: "Rear left")
        case 6:
            direction = String(localized: "Left")
        default:
            direction = String(localized: "Front left")
        }

        return String(
            format: String(localized: "%@ region"),
            direction
        )
    }

    private var gapSectors: [Int] {
        (0..<coverage.sectorCount)
            .filter {
                coverage.observedPitchBandCount(
                    sectorIndex: $0
                ) < ScanCoveragePitchBand.allCases.count
            }
            .sorted {
                let lhs = coverage.observedPitchBandCount(
                    sectorIndex: $0
                )
                let rhs = coverage.observedPitchBandCount(
                    sectorIndex: $1
                )
                if lhs != rhs {
                    return lhs < rhs
                }
                return $0 < $1
            }
    }

    private func missingBandLabels(
        _ sectorIndex: Int
    ) -> String {
        let missing = ScanCoveragePitchBand.allCases
            .filter {
                !coverage.isObserved(
                    sectorIndex: sectorIndex,
                    pitchBand: $0
                )
            }
            .map(pitchBandLabel)

        return missing.joined(separator: " · ")
    }

    private func pitchBandLabel(
        _ band: ScanCoveragePitchBand
    ) -> String {
        switch band {
        case .low:
            return String(localized: "Low")
        case .level:
            return String(localized: "Level")
        case .high:
            return String(localized: "High")
        }
    }

    private func percent(_ fraction: Double) -> String {
        String(
            format: "%d%%",
            Int((fraction * 100).rounded())
        )
    }

    private func directionLabel(_ sectorIndex: Int) -> String {
        let count = max(coverage.sectorCount, 1)
        let normalized =
            ((sectorIndex % count) + count) % count

        switch normalized {
        case 0:
            return String(localized: "Front")
        case 1, 2:
            return String(localized: "Front right")
        case 3:
            return String(localized: "Right")
        case 4, 5:
            return String(localized: "Rear right")
        case 6:
            return String(localized: "Rear")
        case 7, 8:
            return String(localized: "Rear left")
        case 9:
            return String(localized: "Left")
        default:
            return String(localized: "Front left")
        }
    }

    private func verticalBandLabel(
        _ band: SpatialVerticalDisplayBand
    ) -> String {
        switch band {
        case .lowest:
            return String(localized: "Floor band")
        case .lower:
            return String(localized: "Lower band")
        case .middle:
            return String(localized: "Middle band")
        case .upper:
            return String(localized: "Upper band")
        case .highest:
            return String(localized: "Ceiling band")
        }
    }
}


private struct SpatialCoverageMapView: View {
    let summary: SpatialScanCoverageSummary

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                guard let bounds = summary.displayBounds else {
                    return
                }

                let columns = CGFloat(bounds.columnCount)
                let rows = CGFloat(bounds.rowCount)
                let cell = min(
                    size.width / columns,
                    size.height / rows
                )
                let mapWidth = columns * cell
                let mapHeight = rows * cell
                let originX = (size.width - mapWidth) / 2
                let originY = (size.height - mapHeight) / 2

                for z in bounds.minZ...bounds.maxZ {
                    for x in bounds.minX...bounds.maxX {
                        let key = SpatialCoverageCellKey(x: x, z: z)
                        let column = CGFloat(x - bounds.minX)
                        let row = CGFloat(bounds.maxZ - z)
                        let rect = CGRect(
                            x: originX + column * cell + 0.5,
                            y: originY + row * cell + 0.5,
                            width: max(0, cell - 1),
                            height: max(0, cell - 1)
                        )

                        let color: Color
                        switch summary.classification(at: key) {
                        case .observed:
                            color = .green.opacity(0.72)
                        case .weak:
                            color = .orange.opacity(0.72)
                        case .unknown:
                            color = .gray.opacity(0.18)
                        }

                        context.fill(
                            Path(rect),
                            with: .color(color)
                        )
                    }
                }

                if let camera = summary.currentCameraPosition {
                    let gridX =
                        camera.x
                        / summary.cellSizeMeters
                        - Double(bounds.minX)
                    let gridZ =
                        Double(bounds.maxZ + 1)
                        - camera.z
                            / summary.cellSizeMeters
                    let center = CGPoint(
                        x: originX + CGFloat(gridX) * cell,
                        y: originY + CGFloat(gridZ) * cell
                    )
                    let radius = max(3, min(6, cell * 0.28))

                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: center.x - radius,
                                y: center.y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )
                        ),
                        with: .color(.white)
                    )

                    if let heading =
                        summary.currentRelativeHeadingRadians
                    {
                        let length = max(8, cell * 0.9)
                        let end = CGPoint(
                            x:
                                center.x
                                + CGFloat(sin(heading))
                                    * length,
                            y:
                                center.y
                                - CGFloat(cos(heading))
                                    * length
                        )
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: end)
                        context.stroke(
                            path,
                            with: .color(.white),
                            lineWidth: 2
                        )
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if summary.displayBounds == nil {
                    Text("Waiting for spatial observation…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
        }
        .background(
            Color.black.opacity(0.2),
            in: RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
        .accessibilityLabel(
            "Start-relative spatial observation map"
        )
    }
}
