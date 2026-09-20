import Foundation
import SwiftUI
import HTDTCaptureCore

public struct CaptureScanningView: View {
    public let preview: AnyView
    public let coverage: ScanCoverageSummary
    public let observation: ObservationStabilitySummary
    public let spatialCoverage: SpatialScanCoverageSummary
    public let derivedPreview: DerivedShapePreviewSnapshot
    public let evidenceFrameCount: Int
    public let captureEvidenceFrame: () -> Void
    public let endScan: () -> Void

    @State private var showingEndScanReview = false
    @State private var isHUDExpanded = false
    @State private var showingAuthorityHelp = false
    @State private var showingSpatialMap = false
    @State private var showingDerivedPreview = false
    @State private var derivedPreviewMode: DerivedPreviewMode = .observation

    public init(
        preview: AnyView,
        coverage: ScanCoverageSummary,
        observation: ObservationStabilitySummary,
        spatialCoverage: SpatialScanCoverageSummary,
        derivedPreview: DerivedShapePreviewSnapshot,
        evidenceFrameCount: Int,
        captureEvidenceFrame: @escaping () -> Void,
        endScan: @escaping () -> Void
    ) {
        self.preview = preview
        self.coverage = coverage
        self.observation = observation
        self.spatialCoverage = spatialCoverage
        self.derivedPreview = derivedPreview
        self.evidenceFrameCount = evidenceFrameCount
        self.captureEvidenceFrame = captureEvidenceFrame
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

                if coverage.latestTrackingState == .normal,
                   let guidance = coverage.recommendedGuidance
                {
                    directionArrowOverlay(guidance)
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height * 0.43
                        )
                        .allowsHitTesting(false)
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
                        format: String(localized: "Coverage %d%%"),
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

            Text(actionSentence)
                .font(.headline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
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

    private var compactBottomControls: some View {
        VStack(spacing: 7) {
            compactEvidenceSummary

            ProgressView(value: coverage.coverageFraction)
                .progressViewStyle(.linear)
                .tint(.white.opacity(0.9))
                .accessibilityLabel(
                    String(localized: "Direction coverage")
                )

            HStack(spacing: 8) {
                Button(action: captureEvidenceFrame) {
                    Label(
                        "Save evidence frame",
                        systemImage: "camera.fill"
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 38
                    )
                }
                .buttonStyle(.borderedProminent)

                Button(action: requestEndScan) {
                    Label(
                        "End scan",
                        systemImage: "checkmark.circle.fill"
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 38
                    )
                }
                .buttonStyle(.bordered)
            }
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
                Text("Spatial observation")
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
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        Text("Spatial observation")
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
                Text("← Left")
                Spacer()
                Text("Start direction")
                Spacer()
                Text("Right →")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var actionSentence: String {
        if coverage.latestTrackingState == .normal,
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
                        "Show this area again from another angle."
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

    private var spatialCoverageCounts: String {
        String(
            format: String(localized: "%d observed · %d weak"),
            spatialCoverage.observedRegionCount,
            spatialCoverage.weakRegionCount
        )
    }

    private var primaryDerivedShapeLabel: String {
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

            switch selected.kind {
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

        if derivedPreview.wallChain != nil {
            return String(localized: "Observed wall chain")
        }

        return String(localized: "No bounded shape evidence yet")
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

    private func requestEndScan() {
        if shouldReviewCoverageBeforeEnding {
            showingEndScanReview = true
        } else {
            endScan()
        }
    }

    private var shouldReviewCoverageBeforeEnding: Bool {
        coverage.coverageFraction < 0.75
        || coverage.pitchBandCoverageFraction(.low) < 0.50
        || coverage.pitchBandCoverageFraction(.high) < 0.50
        || spatialCoverage.weakRegionCount > 0
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
                        "Overall coverage",
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
