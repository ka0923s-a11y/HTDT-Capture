import Foundation
import SwiftUI
import HTDTCaptureCore

public struct CaptureScanningView: View {
    public let preview: AnyView
    public let coverage: ScanCoverageSummary
    public let observation: ObservationStabilitySummary
    public let derivedPreview: DerivedShapePreviewSnapshot
    public let evidenceFrameCount: Int
    public let captureEvidenceFrame: () -> Void
    public let endScan: () -> Void

    @State private var showingEndScanReview = false
    @State private var derivedPreviewMode: DerivedPreviewMode = .overlay

    public init(
        preview: AnyView,
        coverage: ScanCoverageSummary,
        observation: ObservationStabilitySummary,
        derivedPreview: DerivedShapePreviewSnapshot,
        evidenceFrameCount: Int,
        captureEvidenceFrame: @escaping () -> Void,
        endScan: @escaping () -> Void
    ) {
        self.preview = preview
        self.coverage = coverage
        self.observation = observation
        self.derivedPreview = derivedPreview
        self.evidenceFrameCount = evidenceFrameCount
        self.captureEvidenceFrame = captureEvidenceFrame
        self.endScan = endScan
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            preview
                .ignoresSafeArea()
                .opacity(
                    derivedPreviewMode == .observation
                    ? 0.18
                    : 1
                )

            VStack(spacing: 0) {
                scanStatusHUD
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                if derivedPreview.hasEvidence {
                    DerivedShapePreviewPanel(
                        snapshot: derivedPreview,
                        mode: $derivedPreviewMode
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                Spacer(minLength: 12)

                coveragePanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            if coverage.latestTrackingState == .normal,
               let guidance = coverage.recommendedGuidance
            {
                GeometryReader { geometry in
                    directionArrowOverlay(guidance)
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height * 0.42
                        )
                }
                .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingEndScanReview) {
            ScanCoverageEndReview(
                coverage: coverage,
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
    }

    private var scanStatusHUD: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(
                    trackingLabel,
                    systemImage: trackingSystemImage
                )
                .font(.subheadline.weight(.semibold))

                Spacer()

                Text(
                    String(
                        format: String(localized: "Coverage %d%%"),
                        coveragePercent
                    )
                )
                .font(.subheadline.monospacedDigit())
            }

            HStack(spacing: 8) {
                Label(
                    String(localized: "RoomPlan approximation"),
                    systemImage: "cube.transparent"
                )
                .font(.caption.weight(.semibold))

                Spacer()

                Text(
                    String(
                        format: String(localized: "Observation: %@"),
                        observationStateLabel
                    )
                )
                .font(.caption.weight(.semibold))
            }

            Text(
                String(
                    localized:
                        "RoomPlan lines are a live structural approximation. HTDT observation evidence is collected separately."
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if observation.recheckSuggested {
                recheckBanner
            }

            HStack(alignment: .center, spacing: 12) {
                Text(guidanceText)
                    .font(.headline)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                Spacer(minLength: 8)

                VStack(spacing: 3) {
                    Text("Next direction")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    RelativeGuidanceCompass(
                        coverage: coverage
                    )
                    .frame(width: 74, height: 74)
                }
            }

            HStack(spacing: 14) {
                Label(
                    String(
                        format: String(localized: "Mesh %d"),
                        coverage.latestMeshAnchorCount
                    ),
                    systemImage: "square.3.layers.3d"
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
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
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

    private var coveragePanel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Look-around coverage")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Advisory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<coverage.sectorCount, id: \.self) {
                    sectorIndex in
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
            .frame(height: 42)

            HStack {
                Text("← Left")
                Spacer()
                Text("Start direction")
                Spacer()
                Text("Right →")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(
                "Coverage is guidance only and does not prove geometric completeness."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button(action: captureEvidenceFrame) {
                    Label(
                        "Save evidence frame",
                        systemImage: "camera.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: requestEndScan) {
                    Label(
                        "End scan",
                        systemImage: "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
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
                    Text("Advisory scan coverage")
                } footer: {
                    Text(
                        "This is a trajectory-based guide, not a geometric completeness measurement."
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
