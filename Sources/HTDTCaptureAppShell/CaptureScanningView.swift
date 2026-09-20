import Foundation
import SwiftUI
import HTDTCaptureCore

public struct CaptureScanningView: View {
    public let preview: AnyView
    public let coverage: ScanCoverageSummary
    public let evidenceFrameCount: Int
    public let captureEvidenceFrame: () -> Void
    public let endScan: () -> Void

    @State private var showingEndScanReview = false

    public init(
        preview: AnyView,
        coverage: ScanCoverageSummary,
        evidenceFrameCount: Int,
        captureEvidenceFrame: @escaping () -> Void,
        endScan: @escaping () -> Void
    ) {
        self.preview = preview
        self.coverage = coverage
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

            VStack(spacing: 0) {
                scanStatusHUD
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                Spacer(minLength: 12)

                coveragePanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
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

            Text(guidanceText)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

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

        if coverage.coverageFraction < 0.10 {
            return String(
                localized: "Move slowly and scan the whole room from different heights and angles."
            )
        }

        let lowCoverage =
            coverage.pitchBandCoverageFraction(.low)
        let highCoverage =
            coverage.pitchBandCoverageFraction(.high)

        if lowCoverage < 0.45,
           lowCoverage + 0.10 < highCoverage
        {
            return String(
                localized: "Capture more of the floor line and lower parts of the room."
            )
        }

        if highCoverage < 0.45,
           highCoverage + 0.10 < lowCoverage
        {
            return String(
                localized: "Capture more of the upper walls and ceiling line."
            )
        }

        if let gap = coverage.recommendedGap {
            return String(
                format: String(
                    localized: "Under-observed: %@ · %@"
                ),
                relativeDirectionLabel(
                    sectorIndex: gap.sectorIndex
                ),
                pitchBandLabel(gap.pitchBand)
            )
        }

        return String(
            localized: "Broad look-around coverage reached. Check the RoomPlan overlay for unrecognized surfaces before ending."
        )
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
                            LabeledContent(
                                directionLabel(sectorIndex),
                                value: String(
                                    format: String(
                                        localized: "%d of 3 angles"
                                    ),
                                    coverage.observedPitchBandCount(
                                        sectorIndex: sectorIndex
                                    )
                                )
                            )
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
