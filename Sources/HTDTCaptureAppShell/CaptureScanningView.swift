import Foundation
import SwiftUI
import HTDTCaptureCore
#if os(iOS)
import UIKit
#endif

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
    /// #275: bounded one-shot high-resolution still — the operator
    /// picks a stated purpose; repeated taps reject while one is in
    /// flight.
    public let captureHighResolutionEvidence:
        (HighQualityEvidencePurpose) -> Void
    public let setMovementCapability:
        (ScanMovementCapability) -> Void
    public let endScan: () -> Void
    /// True while the host is committing the End transaction (#279):
    /// scan controls are replaced with an explicit busy state instead
    /// of looking actionable while actions are internally no-op.
    public let isEndingScan: Bool
    /// True while a manual evidence save is still in flight.
    public let isCapturingEvidence: Bool
    /// True while a bounded high-resolution still is in flight
    /// (#275).
    public let isCapturingHighResolutionEvidence: Bool
    /// Frames retained by the bounded automatic selector (#216).
    public let automaticEvidenceCount: Int
    /// Live storage accounting for the working revision (#308):
    /// retained bytes by category, measured device free space, and
    /// the automatic-keyframe budget. Advisory only.
    public let evidenceStorageAdvisory:
        CaptureEvidenceStorageAdvisory?
    /// Live low-light recovery surface (#283).
    public let lowLightGuidanceActive: Bool
    /// #277: bounded camera-source preflight advisory — one card,
    /// advisory only, always with a Continue path.
    public let sourceQualityAdvisory: CameraSourceAdvisory?
    /// Active targeted-object pass status (#250).
    public let targetScanStatus: TargetScanStatus?
    /// #269: live iterative-segmentation interaction state for the
    /// object pass (`.unavailable` when idle or assets unsupported).
    public let segmentationInteraction: SegmentationInteractionState
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
    /// #269: forwards an operator seed/refine gesture as a Core
    /// `SegmentationGesture` (view-normalized points + viewport size);
    /// the coordinator maps it through the display-transform authority.
    public let segmentationGesture:
        (SegmentationGesture) -> Void
    /// #269: "Use" — fuse + persist the accepted mask.
    public let useSegmentation: () -> Void
    /// #269: drop the live run ("Cancel" / "New selection").
    public let cancelSegmentation: () -> Void
    /// #269: explicit operator asset-prep request.
    public let segmentationAssetPrepare: () -> Void
    public let declareNearestUnresolvedRegion:
        (DeclaredRegionReason) -> Void
    public let revokeOperatorRegion:
        (SpatialCoverageCellKey) -> Void
    public let setGuidanceCuesEnabled: (Bool) -> Void
    public let setLoopClosureCheckActive: (Bool) -> Void
    /// #273: records the operator's response to the armed
    /// return-to-start check as advisory provenance.
    public let recordLoopClosureOutcome: (String) -> Void
    /// #273: "Rescan" response — discards the in-progress working
    /// revision entirely (the host's own confirm contract applies).
    public let discardCapture: () -> Void
    /// #277: re-runs the bounded source-quality preflight once.
    public let recheckSourceQuality: () -> Void
    /// #277: dismisses the advisory card (recorded, never gating).
    public let dismissSourceQualityAdvisory: () -> Void
    /// #214/#250: live center-ray probe for the scanning-surface
    /// reticle, so aim-based actions never fire a blind center
    /// raycast.
    public let probePlacementTarget:
        () async -> AnnotationPlacementProbe
    /// #375: commits an operator field note bound to this revision
    /// during scanning — (text, category, needsAttention,
    /// attachLatestEvidence, dictated, anchorRequest). #421: the
    /// anchor request asks the host to validate a subject-point
    /// raycast or record the device viewpoint; an unavailable
    /// anchor degrades to no location rather than fabricating one.
    public let recordFieldNote:
        (String, CaptureFieldNoteCategory, Bool, Bool, Bool,
         CaptureFieldNoteAnchorRequest) -> Void
    /// Latest copilot resolution for this scan (#272); nil until
    /// the operator asks. Advisory only — the suggestion can never
    /// act on the capture itself.
    public let scanCopilotResolution: ScanCopilotResolution?
    /// True while a copilot request is resolving.
    public let isScanCopilotResolving: Bool
    /// #272: asks the host for an advisory next-step suggestion.
    public let requestScanCopilotSuggestion: () -> Void

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
    @State private var composingFieldNote = false
    /// Live reticle probe over the scanning preview (#214/#250).
    @State private var centerProbe = AnnotationPlacementProbe
        .unavailable
    @State private var centerProbeTask: Task<Void, Never>?
    /// Two-tap arm for the loop-check "Rescan" response (#273) —
    /// the discard is destructive, so the first tap only arms the
    /// confirm label.
    @State private var loopRescanArmed = false
    /// Two-tap arm for the always-available Stop control — the only
    /// exit that discards the in-progress capture without ending
    /// into Review.
    @State private var stopScanArmed = false
    // #269: seed/refine interaction state for the preview overlay —
    /// which gesture produces a seed (tap / box / lasso→scribble) and
    /// whether a refinement tap includes or excludes the point.
    @State private var segmentationSeedMode = SegmentationSeedMode.point
    @State private var segmentationRefineInclude = true
    /// Live drag path (view points) for lasso/box strokes on the
    /// preview; cleared when the gesture ends.
    @State private var segmentationDragPoints: [CGPoint] = []
    @State private var segmentationDragAnchor: CGPoint?
#if os(iOS)
    /// #364 §5/§16: on regular width the expanded HUD presents as a
    /// trailing inspector pane instead of a bottom overlay covering
    /// the preview.
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
#endif

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
        isCapturingHighResolutionEvidence: Bool = false,
        automaticEvidenceCount: Int = 0,
        evidenceStorageAdvisory:
            CaptureEvidenceStorageAdvisory? = nil,
        lowLightGuidanceActive: Bool = false,
        sourceQualityAdvisory: CameraSourceAdvisory? = nil,
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
        segmentationInteraction: SegmentationInteractionState =
            .unavailable,
        segmentationGesture: @escaping
            (SegmentationGesture) -> Void = { _ in },
        useSegmentation: @escaping () -> Void = {},
        cancelSegmentation: @escaping () -> Void = {},
        segmentationAssetPrepare: @escaping () -> Void = {},
        declareNearestUnresolvedRegion: @escaping
            (DeclaredRegionReason) -> Void = { _ in },
        revokeOperatorRegion: @escaping
            (SpatialCoverageCellKey) -> Void = { _ in },
        setGuidanceCuesEnabled: @escaping
            (Bool) -> Void = { _ in },
        setLoopClosureCheckActive: @escaping
            (Bool) -> Void = { _ in },
        recordLoopClosureOutcome: @escaping
            (String) -> Void = { _ in },
        discardCapture: @escaping () -> Void = {},
        recheckSourceQuality: @escaping () -> Void = {},
        dismissSourceQualityAdvisory: @escaping () -> Void = {},
        probePlacementTarget: @escaping
            () async -> AnnotationPlacementProbe =
            { .unavailable },
        recordFieldNote: @escaping
            (String, CaptureFieldNoteCategory, Bool, Bool, Bool,
             CaptureFieldNoteAnchorRequest) -> Void
                = { _, _, _, _, _, _ in },
        scanCopilotResolution: ScanCopilotResolution? = nil,
        isScanCopilotResolving: Bool = false,
        requestScanCopilotSuggestion: @escaping () -> Void = {},
        captureEvidenceFrame: @escaping () -> Void,
        captureHighResolutionEvidence: @escaping
            (HighQualityEvidencePurpose) -> Void = { _ in },
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
        self.isCapturingHighResolutionEvidence =
            isCapturingHighResolutionEvidence
        self.automaticEvidenceCount = automaticEvidenceCount
        self.evidenceStorageAdvisory = evidenceStorageAdvisory
        self.lowLightGuidanceActive = lowLightGuidanceActive
        self.sourceQualityAdvisory = sourceQualityAdvisory
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
        self.segmentationInteraction = segmentationInteraction
        self.segmentationGesture = segmentationGesture
        self.useSegmentation = useSegmentation
        self.cancelSegmentation = cancelSegmentation
        self.segmentationAssetPrepare = segmentationAssetPrepare
        self.declareNearestUnresolvedRegion =
            declareNearestUnresolvedRegion
        self.revokeOperatorRegion = revokeOperatorRegion
        self.setGuidanceCuesEnabled = setGuidanceCuesEnabled
        self.setLoopClosureCheckActive =
            setLoopClosureCheckActive
        self.recordLoopClosureOutcome = recordLoopClosureOutcome
        self.discardCapture = discardCapture
        self.recheckSourceQuality = recheckSourceQuality
        self.dismissSourceQualityAdvisory =
            dismissSourceQualityAdvisory
        self.probePlacementTarget = probePlacementTarget
        self.recordFieldNote = recordFieldNote
        self.scanCopilotResolution = scanCopilotResolution
        self.isScanCopilotResolving = isScanCopilotResolving
        self.requestScanCopilotSuggestion =
            requestScanCopilotSuggestion
        self.captureEvidenceFrame = captureEvidenceFrame
        self.captureHighResolutionEvidence =
            captureHighResolutionEvidence
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
                    // #269: the seed/refine input layer lives inside the
                    // preview's own bounds — the view-normalized points
                    // it emits must cover exactly the image region the
                    // recorded display transform maps.
                    .overlay(segmentationGestureSurface)
                    // #73: the framework miniature 3D model renders at
                    // the bottom of the preview — reserve unobstructed
                    // space for it above the bottom controls (and the
                    // expanded bottom HUD when it overlays compact
                    // widths) instead of covering it.
                    .padding(.bottom, previewModelReserve(in: geometry))

                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        compactStatusHUD
                            .padding(.horizontal, 10)
                            .padding(.top, 6)

                        Spacer(minLength: 12)

                        if isHUDExpanded && !expandedHUDIsInspector {
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
                    .frame(maxWidth: .infinity)

                    if isHUDExpanded && expandedHUDIsInspector {
                        expandedHUD(maxHeight: .infinity)
                            .frame(width: 360)
                            .padding(.trailing, 10)
                            .padding(.vertical, 6)
                            .transition(
                                .move(edge: .trailing)
                                    .combined(with: .opacity)
                            )
                    }
                }

                if let motionGuidance {
                    motionGuidanceOverlay(motionGuidance)
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height * 0.43
                        )
                        .allowsHitTesting(false)
                }

                // #214/#250: a live center reticle + hit probe over the
                // shared preview, so aim-based actions ("Scan this
                // object") never execute a blind center raycast — the
                // operator sees the target class + distance first.
                centerReticle
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                    .allowsHitTesting(false)

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
                declaredRegions: declaredRegions,
                guidanceProgress: guidanceProgress,
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
        .sheet(isPresented: $composingFieldNote) {
            FieldNoteComposeSheet(
                allowsEvidenceAttachment: evidenceFrameCount > 0,
                allowsSpatialAnchor: true
            ) { draft in
                recordFieldNote(
                    draft.text,
                    draft.category,
                    draft.needsAttention,
                    draft.attachLatestEvidence,
                    draft.dictated,
                    draft.anchorRequest
                )
            }
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
        .onAppear { startCenterProbe() }
        .onDisappear { centerProbeTask?.cancel() }
    }

    /// Center reticle + live probe label over the scanning preview
    /// (#214/#250). Same probe contract as the annotation camera
    /// sheet: the ring turns green on a hit and the capsule names
    /// the target class + distance; misses show only the dim ring.
    private var centerReticle: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(
                        centerProbe.status == .hit
                            ? Color.green.opacity(0.9)
                            : Color.white.opacity(0.5),
                        lineWidth: 1.5
                    )
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 3, height: 3)
            }
            if centerProbe.status == .hit {
                Text(
                    AnnotationPresentation.probeStatusText(
                        centerProbe
                    )
                )
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
        }
    }

    /// Polls the shared-session center probe ~2x/second for the
    /// scanning reticle. Side-effect-free; cancelled on disappear.
    private func startCenterProbe() {
        centerProbeTask?.cancel()
        centerProbeTask = Task { @MainActor in
            while !Task.isCancelled {
                centerProbe = await probePlacementTarget()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
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
                        DescribedPickerOption(
                            title: String(localized: "Not set"),
                            detail: String(localized:
                                "Leave the flag uncategorized — it still appears in Review.")
                        )
                        .tag(
                            ScanRevisitFlagCategory?.none
                        )
                        ForEach(
                            ScanRevisitFlagCategory.allCases,
                            id: \.self
                        ) { category in
                            DescribedPickerOption(
                                title: MissionPresentation
                                    .scanRevisitFlagCategoryName(
                                        category
                                    ),
                                detail: MissionPresentation
                                    .scanRevisitFlagCategoryDescription(
                                        category
                                    )
                            )
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

    /// #73: vertical space reserved below the preview so the framework
    /// miniature 3D model (rendered at the preview's bottom edge) is
    /// never covered by the bottom control row or the expanded HUD
    /// when it overlays compact widths. On regular width the HUD is a
    /// trailing inspector, so only the control strip is reserved.
    private func previewModelReserve(
        in geometry: GeometryProxy
    ) -> CGFloat {
        // Bottom control row (~54) + its 8pt bottom padding.
        let controls: CGFloat = 62
        guard isHUDExpanded, !expandedHUDIsInspector else {
            return controls
        }
        return controls + geometry.size.height * 0.36 + 8
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
                        format: String(
                            localized: "Directions %d/%d"
                        ),
                        coverage.observedCellCount,
                        coverage.totalCellCount
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
                    : ScanMotionGuidanceCopy.category(for: motionGuidance.action)
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Text(actionSentence)
                .font(CaptureDesign.Typography.taskHeadline)
                .foregroundStyle(
                    endScanGuidance == nil
                    ? Color.primary
                    : CaptureColorRole.attention.color
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
               let note = ScanMotionGuidanceCopy.safetyNote(for: motionGuidance)
            {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            // #283: the low-light prompt is a distinct surface, not
            // folded into generic tracking wording. #364 §5: the
            // compact HUD shows at most one highest-priority advisory
            // — the actionable environment warning outranks transient
            // status text; everything else stays reachable through
            // the expanded details. #277: the one-shot source-quality
            // card shares this slot while it is pending — it is
            // operator-actionable (Recheck) and self-dismisses.
            if let sourceQualityAdvisory {
                sourceQualityCard(sourceQualityAdvisory)
            } else if lowLightGuidanceActive {
                Label(
                    "The room is too dark for reliable visual capture. Turn on normal room lighting while scanning — it can be dimmed again afterward.",
                    systemImage: "lightbulb"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(CaptureColorRole.attention.color)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            } else if let statusMessage,
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
        // VoiceOver reaches the action sentence first: it carries the
        // next-action guidance rather than Canvas drawing order (#342).
        .accessibilitySortPriority(1)
    }

    /// #277: the single source-quality card — smudge and (Stage-B,
    /// disabled by default) low-light findings share one surface so
    /// the HUD never stacks two source warnings. Advisory only:
    /// "Continue anyway" always exists and never gates End.
    @ViewBuilder
    private func sourceQualityCard(
        _ advisory: CameraSourceAdvisory
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if advisory.smudgeSuspected {
                Label(
                    "The camera lens may be smudged — wipe it gently, then tap Recheck.",
                    systemImage: "camera.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(CaptureColorRole.attention.color)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            }
            if advisory.lowLightSuspected {
                Label(
                    "The scene looks dark to the camera; brighter, even lighting improves photo evidence quality.",
                    systemImage: "lightbulb"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(CaptureColorRole.attention.color)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            }
            HStack(spacing: 8) {
                Button(String(localized: "Recheck")) {
                    recheckSourceQuality()
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(String(localized: "Continue anyway")) {
                    dismissSourceQualityAdvisory()
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
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
                .foregroundStyle(CaptureColorRole.informational.color)

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
                .foregroundStyle(CaptureColorRole.attention.color)

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
            // #364 §5: exactly one prominent action at a time — Save
            // evidence leads while coverage is incomplete and yields
            // to End once the scan is ready to finish.
            .scanControlStyle(prominent: !primaryScanReadyToEnd)
            .controlSize(.regular)
            .disabled(isEndingScan || isCapturingEvidence)
            .accessibilityLabel(
                String(localized: "Save evidence frame")
            )

            // #275: a deliberate high-resolution still — the operator
            // states the purpose so the retained evidence keeps honest
            // provenance; at most one ARKit request is in flight.
            Menu {
                Button(
                    String(localized: "Equipment label")
                ) {
                    captureHighResolutionEvidence(.equipmentLabel)
                }
                Button(
                    String(localized: "Targeted object")
                ) {
                    captureHighResolutionEvidence(.targetedObject)
                }
                Button(
                    String(localized: "Reference fixture")
                ) {
                    captureHighResolutionEvidence(.referenceFixture)
                }
                Button(
                    String(localized: "Review evidence")
                ) {
                    captureHighResolutionEvidence(.reviewEvidence)
                }
            } label: {
                Label(
                    isCapturingHighResolutionEvidence
                        ? "Hi-res…"
                        : "Hi-res",
                    systemImage: "camera.aperture"
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(minHeight: 38)
            }
            .scanControlStyle(prominent: false)
            .controlSize(.regular)
            .disabled(
                isEndingScan
                    || isCapturingHighResolutionEvidence
            )
            .accessibilityLabel(
                String(
                    localized: "Save high-resolution evidence"
                )
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

            // #375: operator note bound to the live scan context —
            // timestamps and the latest committed evidence frame are
            // captured by the host, never typed in by hand.
            Button {
                composingFieldNote = true
            } label: {
                Label(
                    "Note",
                    systemImage: "note.text"
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(minHeight: 38)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isEndingScan)
            .accessibilityLabel(
                String(localized: "Add a field note")
            )

            Spacer(minLength: 8)

            // Always-available escape: discards the working revision
            // and returns to Setup. Two taps because it is
            // destructive — the arm label says what happens.
            Button(
                stopScanArmed
                    ? String(
                        localized: "Discard?"
                    )
                    : String(localized: "Stop"),
                role: .destructive
            ) {
                if stopScanArmed {
                    stopScanArmed = false
                    discardCapture()
                } else {
                    stopScanArmed = true
                }
            }
            .font(.callout)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isEndingScan)
            .accessibilityLabel(
                String(
                    localized: stopScanArmed
                        ? "Confirm discard capture"
                        : "Stop scanning"
                )
            )

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
            .scanControlStyle(prominent: primaryScanReadyToEnd)
            .tint(
                endScanGuidance != nil
                ? CaptureColorRole.attention.color
                : (primaryScanReadyToEnd
                    ? CaptureColorRole.success.color : nil)
            )
            .controlSize(.regular)
            .disabled(isEndingScan)
            .accessibilityLabel(
                String(localized: "End scan")
            )
        }
        .onChange(of: isEndingScan) { ending in
            if ending { stopScanArmed = false }
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
                .font(CaptureDesign.Typography.taskHeadline)
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
                CaptureColorRole.attention.color.opacity(0.16),
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
                scanCopilotSection
                directionCoverageSection

                if let storage = evidenceStorageAdvisory {
                    evidenceStorageSection(storage)
                }

                DisclosureGroup(
                    isExpanded: $showingSpatialMap
                ) {
                    VStack(spacing: 8) {
                        SpatialCoverageMapView(
                            summary: spatialCoverage,
                            declaredRegionKeys: Set(
                                declaredRegions.map(\.key)
                            )
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

                        if !spatialCoverage.recentlyEvictedKeys
                            .isEmpty
                        {
                            spatialLegend(
                                "Dropped (capacity)",
                                color: .gray,
                                dashed: true
                            )
                        }

                        if spatialCoverage.usesDepthFallback {
                            Label(
                                "Scene-depth fallback active",
                                systemImage: "viewfinder"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CaptureColorRole.informational.color)
                        }

                        verticalCoverageStrip

                        if spatialCoverage.capacity.evictionCount > 0 {
                            Label(
                                String(
                                    format: String(
                                        localized:
                                            "Coverage map reached its %d-cell limit and dropped %d earlier cells. Dropped cells were observed before — they are not the same as never-observed cells."
                                    ),
                                    spatialCoverage.capacity
                                        .maxRegionCount,
                                    spatialCoverage.capacity
                                        .evictionCount
                                ),
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CaptureColorRole.attention.color)
                        } else if spatialCoverage.capacity.isSaturated {
                            Label(
                                String(
                                    format: String(
                                        localized:
                                            "Coverage map is at its %d-cell limit; scanning new areas drops the least-observed cells."
                                    ),
                                    spatialCoverage.capacity
                                        .maxRegionCount
                                ),
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CaptureColorRole.attention.color)
                        }
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

    /// #364 §5: the expanded HUD is a trailing inspector on regular
    /// width (iPad split layout) — it no longer covers the preview —
    /// and stays a bottom overlay on compact width.
    private var expandedHUDIsInspector: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular
        #else
        return false
        #endif
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
                    if let storage = evidenceStorageAdvisory {
                        Label(
                            storageByteLabel(
                                storage.profile.totalBytes
                            ),
                            systemImage: "internaldrive"
                        )
                        .foregroundStyle(
                            storageBandColor(storage.pressureBand)
                        )
                    }
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

    /// #272: on-demand advisory copilot. The button asks the host for
    /// a suggestion; the chip shows the resolved pick with its source
    /// (deterministic vs model). Nothing here acts on the capture —
    /// the suggestion only rewords already-visible guidance.
    private var scanCopilotSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Copilot")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Advisory")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let resolution = scanCopilotResolution {
                VStack(alignment: .leading, spacing: 3) {
                    Label(
                        ScanCopilotCopy.instruction(
                            for: resolution.suggestion.template
                        ),
                        systemImage: "lightbulb"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        CaptureColorRole.informational.color
                    )

                    if let priority = ScanCopilotCopy
                        .priorityCaption(
                            for: resolution.suggestion.priority
                        )
                    {
                        Text(priority)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                CaptureColorRole.attention.color
                            )
                    }

                    Text(
                        ScanCopilotCopy.sourceCaption(
                            for: resolution
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Button {
                requestScanCopilotSuggestion()
            } label: {
                Label(
                    isScanCopilotResolving
                        ? String(localized: "Resolving…")
                        : String(localized: "What next?"),
                    systemImage: "sparkles"
                )
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isScanCopilotResolving)
            .accessibilityHint(
                String(
                    localized:
                        "Shows an advisory next step. It never starts, stops, or finishes the capture."
                )
            )
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
            // One compact summary instead of 36 near-identical cell
            // labels (#342); the cells stay visual and their state is
            // fully expressed by the summary text.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                String(localized: "Direction coverage grid")
            )
            .accessibilityValue(directionCoverageAccessibilityText)

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
            return guidanceCompletionSentence
        }

        if let motionGuidance {
            let prompt = ScanMotionGuidanceCopy.prompt(for: motionGuidance)
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
                        ScanMotionGuidanceCopy.safetyDisclaimer()
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
                } else {
                    // Missing cells carry their own mark so state is
                    // never color-only (#342).
                    Image(systemName: "minus")
                        .font(.system(size: 6, weight: .black))
                        .foregroundStyle(
                            .white.opacity(0.9)
                        )
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
            .accessibilityHidden(true)
    }

    /// The spoken direction summary (#342) from the same coverage
    /// state the visual grid renders — percent, missing directions by
    /// band, and the deterministic next target.
    private var directionCoverageAccessibilityText: String {
        ScanAccessibilityText.directionCoverage(DirectionCoverageAccessibilitySummary(
                coverage: coverage
            ))
    }

    @ViewBuilder
    private func spatialLegend(
        _ label: LocalizedStringKey,
        color: Color,
        dashed: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(dashed ? 0.35 : 1))
                .overlay {
                    if dashed {
                        Circle()
                            .stroke(
                                color,
                                style: StrokeStyle(
                                    lineWidth: 1,
                                    dash: [2, 1.5]
                                )
                            )
                    }
                }
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
        let base = String(
            format: String(localized: "%d observed · %d weak"),
            spatialCoverage.observedRegionCount,
            spatialCoverage.weakRegionCount
        )
        // #336: dropped cells are reported, never silently forgotten.
        guard spatialCoverage.capacity.evictionCount > 0 else {
            return base
        }
        return base + String(
            format: String(localized: " · %d dropped"),
            spatialCoverage.capacity.evictionCount
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
                        ? CaptureColorRole.attention.color
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

                // #250: live distance to the locked target anchor —
                // the continuous "which object" confirmation while
                // the camera moves around it.
                if let distance = status.distanceToTargetMeters {
                    Text(
                        String(
                            format: String(
                                localized: "Target ~%.1f m"
                            ),
                            distance
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                }

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

                // #269: bounded iterative-segmentation controls inside
                // the same pass card — never a separate workflow.
                segmentationPassSection
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

    /// #269: seed/refine input layer over the live preview. Hit-testable
    /// only inside an object pass while the interaction accepts input;
    /// points are normalized by the preview's own bounds so the
    /// coordinator's recorded display transform stays the sole
    /// mapping authority.
    private var segmentationGestureSurface: some View {
        GeometryReader { geo in
            let active =
                targetScanStatus != nil
                && (segmentationInteraction.phase == .seeding
                    || segmentationInteraction.phase == .maskReady)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                // Live stroke feedback for box/lasso seed gestures.
                if active,
                   segmentationSeedMode == SegmentationSeedMode.lasso,
                   segmentationDragPoints.count > 1
                {
                    Path { path in
                        path.move(to: segmentationDragPoints[0])
                        for point in segmentationDragPoints
                            .dropFirst()
                        {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(Color.accentColor, lineWidth: 2)
                }
                if active,
                   segmentationSeedMode == SegmentationSeedMode.box,
                   let anchor = segmentationDragAnchor,
                   let current = segmentationDragPoints.last
                {
                    Path { path in
                        path.addRect(
                            CGRect(
                                x: min(anchor.x, current.x),
                                y: min(anchor.y, current.y),
                                width: abs(current.x - anchor.x),
                                height: abs(current.y - anchor.y)
                            )
                        )
                    }
                    .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard active else {
                            return
                        }
                        switch (
                            segmentationInteraction.phase,
                            segmentationSeedMode
                        ) {
                        case (.seeding, SegmentationSeedMode.box):
                            if segmentationDragAnchor == nil {
                                segmentationDragAnchor =
                                    value.startLocation
                            }
                            segmentationDragPoints =
                                [value.startLocation, value.location]
                        case (.seeding, SegmentationSeedMode.lasso):
                            segmentationDragPoints
                                .append(value.location)
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        let stroke = segmentationDragPoints
                        segmentationDragPoints = []
                        segmentationDragAnchor = nil
                        guard active,
                              geo.size.width > 0,
                              geo.size.height > 0
                        else {
                            return
                        }
                        func normalize(
                            _ point: CGPoint
                        ) -> NormalizedPoint2D {
                            NormalizedPoint2D(
                                x: Double(
                                    point.x / geo.size.width
                                ),
                                y: Double(
                                    point.y / geo.size.height
                                )
                            )
                        }
                        func send(
                            _ kind: SegmentationGestureKind,
                            _ points: [CGPoint]
                        ) {
                            segmentationGesture(
                                SegmentationGesture(
                                    kind: kind,
                                    viewNormalizedPoints:
                                        points.map(normalize),
                                    viewportWidthPoints:
                                        Double(geo.size.width),
                                    viewportHeightPoints:
                                        Double(geo.size.height)
                                )
                            )
                        }
                        switch segmentationInteraction.phase {
                        case .seeding:
                            switch segmentationSeedMode {
                            case .point:
                                send(.seedPoint, [value.location])
                            case .box:
                                send(
                                    .seedBox,
                                    [
                                        value.startLocation,
                                        value.location,
                                    ]
                                )
                            case .lasso:
                                if stroke.count >= 2 {
                                    send(.seedScribble, stroke)
                                }
                            }
                        case .maskReady:
                            send(
                                segmentationRefineInclude
                                    ? .includePoint
                                    : .excludePoint,
                                [value.location]
                            )
                        default:
                            break
                        }
                    }
            )
            .allowsHitTesting(active)
        }
    }

    /// #269 object-pass block: asset readiness (explicit prep only)
    /// plus the bounded seed→refine→use controls.
    @ViewBuilder
    private var segmentationPassSection: some View {
        if segmentationInteraction.phase != .unavailable,
           targetScanStatus != nil
        {
            Divider()
            switch segmentationInteraction.assetReadiness {
            case .ready:
                segmentationControls
            case .downloading:
                Label(
                    "Segmentation model downloading…",
                    systemImage: "arrow.down.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            case .notReady, .unknown:
                HStack(spacing: 8) {
                    Text(
                        "Segmentation model not on this device"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Prepare") {
                        segmentationAssetPrepare()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            case .failed:
                HStack(spacing: 8) {
                    Text("Segmentation prep failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        segmentationAssetPrepare()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            case .unsupported:
                Text(
                    "Object isolation requires iOS 27 or later"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let detail = segmentationInteraction.detail,
               segmentationInteraction.phase != .accepted
            {
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var segmentationControls: some View {
        switch segmentationInteraction.phase {
        case .seeding:
            VStack(alignment: .leading, spacing: 4) {
                Picker(
                    "Isolation mode",
                    selection: $segmentationSeedMode
                ) {
                    Text("Tap").tag(SegmentationSeedMode.point)
                    Text("Box").tag(SegmentationSeedMode.box)
                    Text("Lasso")
                        .tag(SegmentationSeedMode.lasso)
                }
                .pickerStyle(.segmented)
                Text(
                    "Tap or draw around the aimed object to isolate it"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        case .running:
            Label(
                "Isolating object…",
                systemImage: "square.dashed"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .maskReady:
            VStack(alignment: .leading, spacing: 6) {
                if let maskPixels =
                    segmentationInteraction.maskPixelCount
                {
                    Text(
                        String(
                            format: String(
                                localized:
                                    "Mask: %lld px — tap the object to include, the background to exclude"
                            ),
                            maskPixels
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Picker(
                    "Refinement",
                    selection: $segmentationRefineInclude
                ) {
                    Text("Include").tag(true)
                    Text("Exclude").tag(false)
                }
                .pickerStyle(.segmented)
                .disabled(
                    !segmentationInteraction.canRefine
                )
                HStack(spacing: 10) {
                    Button("Use") { useSegmentation() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("New selection") {
                        cancelSegmentation()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        case .accepted:
            VStack(alignment: .leading, spacing: 4) {
                if let fused =
                    segmentationInteraction.fusedWorldPointCount,
                   fused > 0
                {
                    Text(
                        String(
                            format: String(
                                localized:
                                    "Selection applied — %lld supported depth points joined the pass"
                            ),
                            fused
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Selection saved as 2D evidence only — no depth support under the mask"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Button("New selection") {
                    cancelSegmentation()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .failed:
            HStack(spacing: 8) {
                Text("Isolation failed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Try again") {
                    cancelSegmentation()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .unavailable:
            EmptyView()
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

                // #273 operator responses: every answer is recorded
                // as advisory provenance; the check never corrects
                // coordinates itself.
                HStack(spacing: 8) {
                    Button("Accept") {
                        recordLoopClosureOutcome("accepted")
                        loopRescanArmed = false
                    }
                    Button("Re-observe") {
                        recordLoopClosureOutcome("reobserve")
                        loopRescanArmed = false
                    }
                    Button("Continue scanning") {
                        recordLoopClosureOutcome("continued")
                        loopRescanArmed = false
                    }
                    // Two-tap: discarding the working revision is
                    // destructive, so the first tap only arms the
                    // confirm label.
                    Button(
                        loopRescanArmed
                            ? String(
                                localized:
                                    "Discard this capture"
                            )
                            : String(localized: "Rescan"),
                        role: .destructive
                    ) {
                        if loopRescanArmed {
                            loopRescanArmed = false
                            discardCapture()
                        } else {
                            loopRescanArmed = true
                        }
                    }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isEndingScan)
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

    /// Completion copy keyed on the typed source (issue #296): a
    /// budget- or constraint-terminated scan never reads as
    /// "everything was observed", and the unresolved weak count stays
    /// visible when the source is not `.observed`.
    private var guidanceCompletionSentence: String {
        switch guidanceProgress.completionSource {
        case .observed:
            return String(
                localized:
                    "Scan guidance complete. You can end now or continue for more detail."
            )
        case .weakRegionRetriesExhausted:
            return captureCountPhrase(
                guidanceProgress.unresolvedWeakRegionCount,
                singular: String(
                    localized:
                        "Guidance finished: %lld weak area did not improve after repeated attempts. It remains reviewable in spatial coverage."
                ),
                plural: String(
                    localized:
                        "Guidance finished: %lld weak areas did not improve after repeated attempts. They remain reviewable in spatial coverage."
                )
            )
        case .attemptBudgetExhausted:
            return captureCountPhrase(
                guidanceProgress.unresolvedWeakRegionCount,
                singular: String(
                    localized:
                        "Guidance attempt budget used. %lld weak area may remain — review spatial coverage before ending."
                ),
                plural: String(
                    localized:
                        "Guidance attempt budget used. %lld weak areas may remain — review spatial coverage before ending."
                )
            )
        case .operatorDeclaredUnresolved:
            return captureCountPhrase(
                guidanceProgress.unresolvedWeakRegionCount,
                singular: String(
                    localized:
                        "Guidance finished: %lld weak area was marked intentionally unresolved. It remains reviewable in spatial coverage."
                ),
                plural: String(
                    localized:
                        "Guidance finished: %lld weak areas were marked intentionally unresolved. They remain reviewable in spatial coverage."
                )
            )
        case .movementConstrained:
            return String(
                localized:
                    "Movement-limited scan complete. Movement-dependent checks were skipped; weak or unknown areas may remain."
            )
        case .incomplete:
            return String(
                localized:
                    "Scan guidance complete. You can end now or continue for more detail."
            )
        }
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
            return ScanMotionGuidanceCopy.prompt(for: motionGuidance)
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
                ScanMotionGuidanceCopy.category(for: guidance.action)
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
            ScanMotionGuidanceCopy.prompt(for: guidance)
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
    /// Retained-storage accounting for the working revision (#308).
    /// Shows bytes by category plus the measured device free space and
    /// the automatic-keyframe budget — evidence counts alone no longer
    /// stand in for storage cost. Advisory only: this section never
    /// claims anything about capture completeness.
    private func evidenceStorageSection(
        _ storage: CaptureEvidenceStorageAdvisory
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Storage")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Advisory")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LabeledContent(
                "Retained evidence",
                value: storageByteLabel(
                    storage.profile.totalBytes
                )
            )
            .font(.caption)

            HStack(spacing: 10) {
                if storage.evidenceFrameCount > 0 {
                    Text(
                        String(
                            format:
                                String(
                                    localized:
                                        "%lld frames · %@"
                                ),
                            Int64(storage.evidenceFrameCount),
                            storageByteLabel(
                                storage.profile.framePixelBytes
                            )
                        )
                    )
                }
                if storage.depthEvidenceCount > 0 {
                    Text(
                        String(
                            format:
                                String(
                                    localized:
                                        "%lld depth · %@"
                                ),
                            Int64(storage.depthEvidenceCount),
                            storageByteLabel(
                                storage.profile
                                    .depthConfidenceBytes
                            )
                        )
                    )
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if storage.profile.meshBytes > 0 {
                    Text(
                        String(
                            format:
                                String(
                                    localized: "Mesh %@"
                                ),
                            storageByteLabel(
                                storage.profile.meshBytes
                            )
                        )
                    )
                }
                if storage.profile.roomPlanBytes > 0 {
                    Text(
                        String(
                            format:
                                String(
                                    localized:
                                        "RoomPlan %@"
                                ),
                            storageByteLabel(
                                storage.profile.roomPlanBytes
                            )
                        )
                    )
                }
                if storage.profile.previewAndDerivedBytes > 0 {
                    Text(
                        String(
                            format:
                                String(
                                    localized:
                                        "Derived %@"
                                ),
                            storageByteLabel(
                                storage.profile
                                    .previewAndDerivedBytes
                            )
                        )
                    )
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Text("Device free")
                    .font(.caption)
                Spacer()
                if let free = storage.deviceAvailableBytes {
                    Text(storageByteLabel(free))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            storageBandColor(
                                storage.pressureBand
                            )
                        )
                } else {
                    Text(String(localized: "Unknown"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if storage.pressureBand == .warning
                || storage.pressureBand == .critical
            {
                Text(
                    storage.pressureBand == .critical
                        ? String(
                            localized:
                                "Very little free storage remains; capture may stop early."
                        )
                        : String(
                            localized:
                                "Free storage is running low for this capture."
                        )
                )
                .font(.caption2)
                .foregroundStyle(
                    storageBandColor(storage.pressureBand)
                )
            }

            if let budget = storage.keyframeBudget {
                LabeledContent(
                    "Auto evidence",
                    value: String(
                        format: String(
                            localized:
                                "%lld/%lld frames · %@/%@"
                        ),
                        Int64(budget.retainedFrameCount),
                        Int64(budget.maximumRetainedFrames),
                        storageByteLabel(
                            Int64(budget.retainedEstimatedBytes)
                        ),
                        storageByteLabel(
                            Int64(budget.maximumRetainedBytes)
                        )
                    )
                )
                .font(.caption)
            }
        }
        .padding(10)
        .background(
            Color.black.opacity(0.18),
            in: RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
    }

    private func storageByteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }

    private func storageBandColor(
        _ band: CaptureStoragePressureBand
    ) -> Color {
        switch band {
        case .nominal:
            return .secondary
        case .warning:
            return .orange
        case .critical:
            return .red
        case .unknown:
            return .secondary
        }
    }
}

/// Localized display name for a principal direction — the same
/// octant vocabulary VoiceOver summaries use (#342).
private func octantDisplayName(
    _ octant: ScanDirectionOctant
) -> String {
    switch octant {
    case .front:
        return String(localized: "Front")
    case .frontRight:
        return String(localized: "Front right")
    case .right:
        return String(localized: "Right")
    case .rearRight:
        return String(localized: "Rear right")
    case .rear:
        return String(localized: "Rear")
    case .rearLeft:
        return String(localized: "Rear left")
    case .left:
        return String(localized: "Left")
    case .frontLeft:
        return String(localized: "Front left")
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
    let declaredRegions: [DeclaredCoverageRegion]
    /// Global unresolved-weak accounting (#347): the display window
    /// is presentation scope only, so the review must distinguish
    /// retained weak regions beyond the current map view from the
    /// unknown cells inside it.
    let guidanceProgress: ScanGuidanceProgress
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
                    if guidanceProgress.remoteWeakRegionCount > 0 {
                        LabeledContent(
                            "Weak beyond map view",
                            value: String(
                                guidanceProgress
                                    .remoteWeakRegionCount
                            )
                        )
                    }
                    LabeledContent(
                        "Unknown cells in map view",
                        value: String(
                            spatialCoverage.displayUnknownRegionCount
                        )
                    )
                    if spatialCoverage.capacity.evictionCount > 0 {
                        LabeledContent(
                            "Dropped for capacity",
                            value: String(
                                format: String(
                                    localized:
                                        "%d of %d cells"
                                ),
                                spatialCoverage.capacity
                                    .evictionCount,
                                spatialCoverage.capacity
                                    .maxRegionCount
                            )
                        )
                        Text(
                            "The coverage map reached its live cell budget and dropped the least-observed cells. A dropped cell was observed before; it is not the same as a never-observed unknown cell."
                        )
                        .font(.caption)
                        .foregroundStyle(CaptureColorRole.attention.color)
                    }

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

                    if !droppedSpatialLabels.isEmpty {
                        Text(
                            String(
                                format: String(
                                    localized: "Dropped: %@"
                                ),
                                droppedSpatialLabels
                                    .prefix(4)
                                    .joined(separator: " · ")
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Spatial coverage")
                } footer: {
                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(
                            "Spatial coverage is advisory. Unknown means no observation authority, not a missing wall, and it is never a finalization gate."
                        )
                        Text(
                            "Direction names are relative to your starting facing direction (marked Start direction), not to the room's front."
                        )
                    }
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
        .onAppear {
            announceReviewSummary()
        }
    }

    /// Spoken coverage summary when the review opens (#342): the same
    /// semantic state the haptic/spoken cues consume, composed into
    /// one announcement so the review state is never visual-only.
    private func announceReviewSummary() {
        #if os(iOS)
        let direction = ScanAccessibilityText.directionCoverage(
            DirectionCoverageAccessibilitySummary(coverage: coverage)
        )
        let spatial = ScanAccessibilityText.spatialCoverage(
            SpatialCoverageAccessibilitySummary(
                coverage: spatialCoverage,
                declaredRegionKeys: Set(
                    declaredRegions.map(\.key)
                )
            )
        )
        UIAccessibility.post(
            notification: .announcement,
            argument: direction + " " + spatial
        )
        #endif
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

    /// Previously observed cells the capacity budget dropped inside
    /// the current map view (#336) — labeled so 'unknown' is never
    /// conflated with 'forgotten'.
    private var droppedSpatialLabels: [String] {
        guard let bounds = spatialCoverage.displayBounds else {
            return []
        }

        var labels: Set<String> = []
        for z in bounds.minZ...bounds.maxZ {
            for x in bounds.minX...bounds.maxX {
                let key = SpatialCoverageCellKey(x: x, z: z)
                guard spatialCoverage.wasRecentlyEvicted(at: key)
                else {
                    continue
                }
                labels.insert(spatialRegionLabel(key))
            }
        }
        return labels.sorted()
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
        let direction = octantDisplayName(
            ScanDirectionOctant(
                azimuthRadians: atan2(x, z)
            )
        )
        let angle = atan2(x, z)

        // #343: labels are start-relative; the scan's reference yaw
        // is the operator's arbitrary start heading, never a room
        // 'Front'.
        return String(
            format: String(localized: "Region %@"),
            StartRelativeDirectionCopy.octantName(
                StartRelativeDirection
                    .octant(forRelativeAngleRadians: angle)
            )
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
        StartRelativeDirectionCopy.sectorLabel(
            sectorIndex: sectorIndex,
            sectorCount: coverage.sectorCount
        )
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

/// Localized direction copy for coverage surfaces (#343). Every label
/// is relative to the operator's start heading — captured as the
/// scan's reference yaw — never an unqualified room 'Front'/'Rear'.
/// A confirmed room reference frame (#232) is the only authority that
/// may rename these, and only through its exact reference yaw.
private enum StartRelativeDirectionCopy {
    static func sectorLabel(
        sectorIndex: Int,
        sectorCount: Int
    ) -> String {
        let signed = StartRelativeDirection.sectorSignedDegrees(
            sectorIndex: sectorIndex,
            sectorCount: sectorCount
        )
        switch signed {
        case 0:
            return String(localized: "Start direction")
        case 180, -180:
            return String(localized: "Behind start")
        case let value where value > 0:
            return String(
                format: String(
                    localized: "%d° right of start"
                ),
                value
            )
        default:
            return String(
                format: String(
                    localized: "%d° left of start"
                ),
                -signed
            )
        }
    }

    static func octantName(
        _ octant: StartRelativeDirection.Octant
    ) -> String {
        switch octant {
        case .ahead:
            return String(localized: "ahead of start")
        case .aheadRight:
            return String(localized: "ahead-right of start")
        case .right:
            return String(localized: "right of start")
        case .behindRight:
            return String(localized: "behind-right of start")
        case .behind:
            return String(localized: "behind start")
        case .behindLeft:
            return String(localized: "behind-left of start")
        case .left:
            return String(localized: "left of start")
        case .aheadLeft:
            return String(localized: "ahead-left of start")
        }
    }
}


private struct SpatialCoverageMapView: View {
    let summary: SpatialScanCoverageSummary
    /// Regions the operator marked intentionally unresolved (#257):
    /// excluded from the prioritized weak-region readout.
    var declaredRegionKeys: Set<SpatialCoverageCellKey> = []

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

                        let classification =
                            summary.classification(at: key)
                        let color: Color
                        switch classification {
                        case .observed:
                            color = .green.opacity(0.72)
                        case .weak:
                            color = .orange.opacity(0.72)
                        case .unknown:
                            color = .gray.opacity(0.18)
                        }

                        let cellPath = Path(rect)
                        // Shape separates state from color (#342):
                        // observed fills + a center dot, weak fills +
                        // a diagonal hatch, unknown is border-only.
                        if classification == .unknown {
                            context.stroke(
                                cellPath,
                                with: .color(
                                    .gray.opacity(0.4)
                                ),
                                lineWidth: 1
                            )
                        } else {
                            context.fill(
                                cellPath,
                                with: .color(color)
                            )
                            if classification == .weak {
                                var hatch = Path()
                                hatch.move(
                                    to: CGPoint(
                                        x: rect.minX,
                                        y: rect.maxY
                                    )
                                )
                                hatch.addLine(
                                    to: CGPoint(
                                        x: rect.maxX,
                                        y: rect.minY
                                    )
                                )
                                context.stroke(
                                    hatch,
                                    with: .color(
                                        .black.opacity(0.55)
                                    ),
                                    lineWidth: 1
                                )
                            } else {
                                let dot = rect.width * 0.2
                                context.fill(
                                    Path(
                                        ellipseIn: CGRect(
                                            x: rect.midX - dot / 2,
                                            y: rect.midY - dot / 2,
                                            width: dot,
                                            height: dot
                                        )
                                    ),
                                    with: .color(
                                        .black.opacity(0.6)
                                    )
                                )
                            }
                        }
                        context.fill(
                            Path(rect),
                            with: .color(color)
                        )

                        // #336: a cell dropped by the capacity budget
                        // is drawn as a dashed outline, distinct from
                        // a never-observed unknown cell.
                        if summary.wasRecentlyEvicted(at: key) {
                            context.stroke(
                                Path(rect),
                                with: .color(.gray.opacity(0.7)),
                                style: StrokeStyle(
                                    lineWidth: 1,
                                    dash: [2, 1.5]
                                )
                            )
                        }
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
        // The Canvas is one element; the full semantic map state is
        // delivered as the summary value (#342).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Start-relative spatial observation map"
        )
        .accessibilityValue(
            ScanAccessibilityText.spatialCoverage(
                SpatialCoverageAccessibilitySummary(
                    coverage: summary,
                    declaredRegionKeys: declaredRegionKeys
                ))
        )
    }
}

private extension View {
    /// #364 §5: the bottom scan controls carry exactly one prominent
    /// action at a time — the call site decides which control is
    /// primary for the current scan state.
    @ViewBuilder
    func scanControlStyle(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
