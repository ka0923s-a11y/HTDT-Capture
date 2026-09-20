import Foundation
import SwiftUI
import HTDTCaptureCore

public struct CaptureScanningView: View {
    @State private var isEndScanReviewPresented = false

    public let preview: AnyView
    public let coverage: ScanCoverageSummary
    public let evidenceFrameCount: Int
    public let captureEvidenceFrame: () -> Void
    public let endScan: () -> Void

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
        .sheet(isPresented: $isEndScanReviewPresented) {
            EndScanGapReviewView(
                coverage: coverage,
                continueScanning: {
                    isEndScanReviewPresented = false
                },
                endAnyway: {
                    isEndScanReviewPresented = false
                    endScan()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

                Button {
                    isEndScanReviewPresented = true
                } label: {
                    Label(
                        "Review & end",
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


private struct EndScanGapReviewView: View {
    let coverage: ScanCoverageSummary
    let continueScanning: () -> Void
    let endAnyway: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    coverageGrid
                    gapGuidance
                    authorityNote
                    actions
                }
                .padding()
            }
            .navigationTitle("Check scan coverage")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Advisory coverage")
                        .font(.headline)
                    Text(
                        String(
                            format: String(localized: "%d of %d view cells observed"),
                            coverage.observedCellCount,
                            coverage.totalCellCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(coveragePercent)%")
                    .font(.title2.monospacedDigit().bold())
            }

            pitchRow(
                title: String(localized: "Lower room"),
                fraction: coverage.pitchBandCoverageFraction(.low)
            )
            pitchRow(
                title: String(localized: "Eye level"),
                fraction: coverage.pitchBandCoverageFraction(.level)
            )
            pitchRow(
                title: String(localized: "Upper room"),
                fraction: coverage.pitchBandCoverageFraction(.high)
            )
        }
        .padding(14)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var coverageGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coverage map")
                .font(.headline)

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<coverage.sectorCount, id: \.self) {
                    sectorIndex in
                    VStack(spacing: 2) {
                        cell(sectorIndex, .high)
                        cell(sectorIndex, .level)
                        cell(sectorIndex, .low)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 50)

            HStack {
                Text("← Left")
                Spacer()
                Text("Start direction")
                Spacer()
                Text("Right →")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label("Observed", systemImage: "checkmark.square.fill")
                Label("Needs another look", systemImage: "square.dashed")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var gapGuidance: some View {
        if let gap = coverage.recommendedGap {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "Likely capture gap",
                    systemImage: "viewfinder.trianglebadge.exclamationmark"
                )
                .font(.headline)

                Text(
                    String(
                        format: String(localized: "Look again toward %@ at %@ height."),
                        relativeDirectionLabel(gap.sectorIndex),
                        pitchBandLabel(gap.pitchBand)
                    )
                )

                Text(
                    String(
                        format: String(localized: "%d advisory cells remain under-observed."),
                        remainingCellCount
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 16)
            )
        } else {
            Label(
                "No advisory direction gaps remain.",
                systemImage: "checkmark.seal.fill"
            )
            .font(.headline)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
    }

    private var authorityNote: some View {
        Text(
            "This coverage model only tracks camera viewing directions and heights. It does not prove that every wall, object, opening, or surface was captured."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: continueScanning) {
                Label(
                    "Continue scanning",
                    systemImage: "camera.viewfinder"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive, action: endAnyway) {
                Label(
                    "End anyway",
                    systemImage: "checkmark.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func pitchRow(
        title: String,
        fraction: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
        }
    }

    private func cell(
        _ sectorIndex: Int,
        _ band: ScanCoveragePitchBand
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

    private var coveragePercent: Int {
        Int((coverage.coverageFraction * 100).rounded())
    }

    private var remainingCellCount: Int {
        max(0, coverage.totalCellCount - coverage.observedCellCount)
    }

    private func pitchBandLabel(
        _ band: ScanCoveragePitchBand
    ) -> String {
        switch band {
        case .low:
            return String(localized: "low")
        case .level:
            return String(localized: "eye-level")
        case .high:
            return String(localized: "high")
        }
    }

    private func relativeDirectionLabel(
        _ sectorIndex: Int
    ) -> String {
        let normalized =
            ((sectorIndex % coverage.sectorCount)
             + coverage.sectorCount)
            % coverage.sectorCount

        switch normalized {
        case 0:
            return String(localized: "front")
        case 1, 2:
            return String(localized: "front-right")
        case 3:
            return String(localized: "right")
        case 4, 5:
            return String(localized: "rear-right")
        case 6:
            return String(localized: "rear")
        case 7, 8:
            return String(localized: "rear-left")
        case 9:
            return String(localized: "left")
        default:
            return String(localized: "front-left")
        }
    }
}
