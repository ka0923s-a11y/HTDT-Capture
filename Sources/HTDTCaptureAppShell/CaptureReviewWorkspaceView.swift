import Foundation
import SwiftUI
import HTDTCaptureCore
#if os(iOS)
import UIKit
#endif

/// The post-End Review workspace (issue #213), reused read-only for
/// persisted captures (issue #294). Presents the captured room as a
/// visual artifact first: plan preview, per-frame evidence gallery,
/// committed annotations, opening review, and the room reference
/// frame. When `readOnly` is false, per-frame privacy deletion (#241),
/// room-frame capture (#232), and opening disposition (#231) remain
/// live; when `spatialCaptureSealed` is true, live-capture actions are
/// additionally hidden (issue #276).
public struct CaptureReviewWorkspaceView: View {
    public let model: CaptureReviewWorkspaceModel
    /// Live-edit actions; unused in read-only mode.
    public let removeEvidenceFrame: (EvidenceFrameID) async -> Void
    public let openingReviewCandidates:
        () async -> [RoomOpeningCandidate]?
    public let commitOpeningReview:
        ([RoomOpeningCandidate]) async -> Bool
    public let captureRoomFrameOrigin: () -> Void
    public let confirmRoomReferenceFrame: () -> Void
    public let roomFrameOriginPending: WorldPoint3D?

    @State private var openings: [RoomOpeningCandidate]?
    @State private var openingSaveState: String?
    @State private var confirmingFrameRemoval:
        EvidenceFrameID?

    public init(
        model: CaptureReviewWorkspaceModel,
        roomFrameOriginPending: WorldPoint3D? = nil,
        removeEvidenceFrame: @escaping
            (EvidenceFrameID) async -> Void = { _ in },
        openingReviewCandidates: @escaping
            () async -> [RoomOpeningCandidate]? = { nil },
        commitOpeningReview: @escaping
            ([RoomOpeningCandidate]) async -> Bool = { _ in false },
        captureRoomFrameOrigin: @escaping () -> Void = {},
        confirmRoomReferenceFrame: @escaping () -> Void = {}
    ) {
        self.model = model
        self.roomFrameOriginPending = roomFrameOriginPending
        self.removeEvidenceFrame = removeEvidenceFrame
        self.openingReviewCandidates = openingReviewCandidates
        self.commitOpeningReview = commitOpeningReview
        self.captureRoomFrameOrigin = captureRoomFrameOrigin
        self.confirmRoomReferenceFrame = confirmRoomReferenceFrame
    }

    public var body: some View {
        List {
            if model.spatialCaptureSealed && !model.readOnly {
                Section {
                    Text(
                        "Live spatial capture is sealed for finalization. Labels, roles, equipment, and scalar values can still be corrected; raycast placement, orientation capture, and additional scanning are unavailable."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("RoomPlan result") {
                if let metadata = model.roomMetadata {
                    LabeledContent(
                        "Raw payload",
                        value: metadata.rawPayloadPath
                    )
                    .font(.caption)
                    LabeledContent(
                        "Processed",
                        value:
                            metadata.processedPayloadPath ?? "—"
                    )
                    .font(.caption)
                    if let summary = metadata.summary,
                       let dims = summary.dimensionsMeters
                    {
                        LabeledContent(
                            "Dimensions",
                            value: String(
                                format: "%.2f × %.2f × %.2f m",
                                dims.xMeters,
                                dims.yMeters,
                                dims.zMeters
                            )
                        )
                    }
                } else {
                    Text("No RoomPlan lineage in this capture")
                        .foregroundStyle(.secondary)
                }
                if let plan = model.planPreview {
                    RoomPlanPreviewCanvas(model: plan)
                        .frame(height: 220)
                        .accessibilityLabel(
                            "Room plan preview"
                        )
                } else {
                    Text(
                        "Plan preview unavailable on this platform or payload"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section(
                model.readOnly
                    ? "Evidence frames"
                    : "Visual evidence review"
            ) {
                if model.evidenceItems.isEmpty {
                    Text("No evidence frames retained")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.evidenceItems) { item in
                    evidenceRow(item)
                }
                if !model.readOnly {
                    Text(
                        "Removing an unreferenced frame deletes its pixels, depth, confidence, and preview permanently. Closing and referenced evidence is always retained."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if !model.annotations.isEmpty {
                Section("Annotations") {
                    ForEach(
                        model.annotations,
                        id: \.entityID
                    ) { entity in
                        let entityType = entity.type.rawValue
                        let entityID =
                            entity.entityID.description
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entity.label)
                                .font(.headline)
                            Text(
                                entityType + " · " + entityID
                                    + operatorSuffix(
                                        entity.authorOperatorID
                                    )
                            )
                            .font(.caption.monospaced())
                        }
                    }
                }
            }

            if !model.measurements.isEmpty {
                Section("Measurements") {
                    ForEach(
                        model.measurements,
                        id: \.measurementID
                    ) { measurement in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            LabeledContent(
                                measurement.quantityType,
                                value: measurement.measurementID
                                    .description
                            )
                            .font(.caption)
                            if let authority =
                                measurement.instrumentAuthority,
                               let profile = model.instruments
                                   .first(where: {
                                       $0.instrumentID
                                           == authority
                                           .instrumentID
                                           && $0.profileVersion
                                           == authority
                                           .profileVersion
                                   })
                            {
                                Text(
                                    [
                                        profile.manufacturer,
                                        profile.model,
                                        profile.serialOrAssetID
                                            .map {
                                                "serial " + $0
                                            },
                                        "v"
                                            + String(
                                                authority
                                                    .profileVersion
                                            ),
                                    ]
                                    .compactMap { $0 }
                                    .joined(separator: " ")
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !model.operatorProfiles.isEmpty {
                Section("Operators") {
                    ForEach(
                        model.operatorProfiles,
                        id: \.operatorID
                    ) { profile in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(profile.displayName)
                            Text(
                                [
                                    profile.organization,
                                    profile.role,
                                ]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.fieldEvidence.isEmpty {
                Section("Field evidence") {
                    ForEach(
                        model.fieldEvidence,
                        id: \.evidenceID
                    ) { record in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(record.title)
                            Text(
                                [
                                    FieldAuthorityPresentation
                                        .evidenceKindName(
                                            record.kind
                                        ),
                                    record.acquisition.rawValue,
                                    record.asset?.assetPath
                                        ?? record.asset?.frameRef,
                                ]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            )
                            .font(.caption.monospaced())
                            if let operatorID = record.operatorID {
                                Text(
                                    "author: "
                                        + operatorName(
                                            operatorID
                                        )
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !model.instruments.isEmpty {
                Section("Measurement instruments") {
                    ForEach(
                        model.instruments,
                        id: \.id
                    ) { instrument in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                [
                                    instrument.manufacturer,
                                    instrument.model,
                                ]
                                .compactMap { $0 }
                                .joined(separator: " ")
                            )
                            Text(
                                [
                                    instrument
                                        .serialOrAssetID
                                        .map {
                                            "serial " + $0
                                        },
                                    FieldAuthorityPresentation
                                        .calibrationStateName(
                                            instrument
                                                .calibrationState
                                        ),
                                    instrument.calibrationDate,
                                    "v"
                                        + String(
                                            instrument
                                                .profileVersion
                                        ),
                                ]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.settingsObservations.isEmpty {
                Section("Installed settings") {
                    ForEach(
                        model.settingsObservations,
                        id: \.observationID
                    ) { observation in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(observation.targetRef)
                                .font(.caption.monospaced())
                            Text(
                                "\(observation.settings.count) setting(s) · "
                                    + observation.recordedAtUTC
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.wiringRoutes.isEmpty {
                Section("As-built wiring") {
                    ForEach(
                        model.wiringRoutes,
                        id: \.routeID
                    ) { route in
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(route.cableType)
                            Text(
                                [
                                    FieldAuthorityPresentation
                                        .routeStateName(
                                            route.state
                                        ),
                                    route.serviceType,
                                    "\(route.segments.count) segment(s)",
                                ]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Opening review") {
                if let review = model.openingReview {
                    Text(
                        "\(review.openings.count) candidate(s) recorded"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if model.readOnly {
                    ForEach(
                        model.openingReview?.openings ?? [],
                        id: \.openingID
                    ) { opening in
                        openingRow(opening, interactive: false)
                    }
                } else {
                    Button("Load opening candidates") {
                        Task {
                            openings =
                                await openingReviewCandidates()
                        }
                    }
                    ForEach(
                        openings
                            ?? model.openingReview?.openings
                                ?? [],
                        id: \.openingID
                    ) { opening in
                        openingRow(opening, interactive: true)
                    }
                    if openings != nil {
                        Button("Save opening review") {
                            guard let openings else { return }
                            Task {
                                let ok =
                                    await commitOpeningReview(
                                        openings
                                    )
                                openingSaveState = ok
                                    ? "Saved"
                                    : "Save failed"
                            }
                        }
                    }
                    if let openingSaveState {
                        Text(openingSaveState)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Room reference frame") {
                if let frame = model.roomReferenceFrame {
                    LabeledContent(
                        "Origin (m)",
                        value: String(
                            format: "%.2f, %.2f, %.2f",
                            frame.originMeters.x,
                            frame.originMeters.y,
                            frame.originMeters.z
                        )
                    )
                    LabeledContent(
                        "Front",
                        value: String(
                            format: "%.2f, %.2f, %.2f",
                            frame.frontDirection.x,
                            frame.frontDirection.y,
                            frame.frontDirection.z
                        )
                    )
                    LabeledContent(
                        "Confirmed",
                        value: frame.confirmedAtUTC
                    )
                } else {
                    Text("No room reference frame confirmed")
                        .foregroundStyle(.secondary)
                }
                if !model.readOnly
                    && !model.spatialCaptureSealed
                {
                    Text(
                        "Stand at the intended room origin, confirm, then aim toward the room front and confirm the second point. The frame binds to the current coordinate space only."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button(
                        roomFrameOriginPending == nil
                            ? "Mark room origin"
                            : "Room origin captured"
                    ) {
                        captureRoomFrameOrigin()
                    }
                    .disabled(roomFrameOriginPending != nil)
                    if roomFrameOriginPending != nil {
                        Button("Confirm room front") {
                            confirmRoomReferenceFrame()
                        }
                    }
                }
            }

            if !model.issues.isEmpty {
                Section("Workspace issues") {
                    ForEach(model.issues, id: \.self) { issue in
                        Text(issue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(
            model.readOnly ? "Persisted capture" : "Review workspace"
        )
        .confirmationDialog(
            "Remove evidence frame?",
            isPresented: Binding(
                get: { confirmingFrameRemoval != nil },
                set: { shown in
                    if !shown { confirmingFrameRemoval = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: confirmingFrameRemoval
        ) { frameID in
            Button("Remove frame", role: .destructive) {
                Task {
                    await removeEvidenceFrame(frameID)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(
                "Permanently deletes this frame's pixels, depth, confidence, and preview from the working capture."
            )
        }
    }

    @ViewBuilder
    private func evidenceRow(
        _ item: ReviewEvidenceItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.frameID.description)
                .font(.caption.monospaced())
            LabeledContent(
                "Bytes",
                value: String(item.byteCount)
            )
            LabeledContent(
                "Kept because",
                value: retentionLabel(item.retentionReason)
            )
            if !item.referencedBy.isEmpty {
                Text(
                    "Referenced by "
                        + item.referencedBy.joined(
                            separator: ", "
                        )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            #if os(iOS)
            if let url = item.previewFileURL {
                AsyncPreviewImage(url: url)
                    .frame(height: 140)
            }
            #endif
            if item.removable {
                Button("Remove frame", role: .destructive) {
                    confirmingFrameRemoval = item.frameID
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func openingRow(
        _ opening: RoomOpeningCandidate,
        interactive: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(
                opening.kind.rawValue,
                value: opening.disposition.rawValue
            )
            Text(opening.sourceRef)
                .font(.caption2.monospaced())
            if interactive {
                HStack(spacing: 8) {
                    Button("Confirm") {
                        setDisposition(.confirmed, on: opening)
                    }
                    Button("Needs scan") {
                        setDisposition(
                            .needsMoreScanning,
                            on: opening
                        )
                    }
                    Button("Ignore") {
                        setDisposition(
                            .intentionallyIgnored,
                            on: opening
                        )
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private func setDisposition(
        _ disposition: RoomOpeningDisposition,
        on opening: RoomOpeningCandidate
    ) {
        guard var current = openings else { return }
        current = OpeningReviewEditor.setDisposition(
            disposition,
            openingID: opening.openingID,
            in: current,
            reviewedAtUTC: BundleTimestamp.utcString(
                from: Date()
            )
        ) ?? current
        openings = current
    }

    private func operatorName(
        _ id: OperatorProfileID
    ) -> String {
        model.operatorProfiles.first(where: {
            $0.operatorID == id
        })?.displayName ?? id.description
    }

    private func operatorSuffix(
        _ id: OperatorProfileID?
    ) -> String {
        guard let id else { return "" }
        return " · author: " + operatorName(id)
    }

    private func retentionLabel(
        _ reason: EvidenceRetentionReason
    ) -> String {
        switch reason {
        case .endBoundary:
            return "Closing evidence"
        case .linkedToAuthority:
            return "Referenced evidence"
        case .operatorSaved:
            return "Optional visual frame"
        }
    }
}

/// The plan-projection canvas for the Review workspace (issue #213):
/// walls as segments, openings/objects as markers, drawn from the
/// platform-independent `RoomPlanPreviewModel`.
public struct RoomPlanPreviewCanvas: View {
    public let model: RoomPlanPreviewModel

    public init(model: RoomPlanPreviewModel) {
        self.model = model
    }

    public var body: some View {
        Canvas { context, size in
            let spanX = max(model.maxX - model.minX, 0.01)
            let spanZ = max(model.maxZ - model.minZ, 0.01)
            let scale = min(
                Double(size.width) / spanX,
                Double(size.height) / spanZ
            ) * 0.9
            let offsetX =
                (Double(size.width) - spanX * scale) / 2
            let offsetY =
                (Double(size.height) - spanZ * scale) / 2

            func point(_ x: Double, _ z: Double) -> CGPoint {
                CGPoint(
                    x: offsetX
                        + (x - model.minX) * scale,
                    y: offsetY
                        + (z - model.minZ) * scale
                )
            }

            for wall in model.walls {
                var path = Path()
                path.move(
                    to: point(wall.startX, wall.startZ)
                )
                path.addLine(
                    to: point(wall.endX, wall.endZ)
                )
                context.stroke(
                    path,
                    with: .color(.primary),
                    lineWidth: 2
                )
            }

            for marker in model.markers {
                let p = point(marker.x, marker.z)
                let color: Color =
                    switch marker.kind {
                    case .door: .green
                    case .window: .blue
                    case .opening: .teal
                    case .object: .gray
                    case .annotation: .orange
                    case .roomFrameOrigin: .red
                    case .roomFrameFront: .purple
                    }
                let rect = CGRect(
                    x: p.x - 4,
                    y: p.y - 4,
                    width: 8,
                    height: 8
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(color)
                )
                if let dirX = marker.dirX,
                   let dirZ = marker.dirZ
                {
                    let len = max(
                        (dirX * dirX + dirZ * dirZ)
                            .squareRoot(),
                        0.001
                    )
                    var arrow = Path()
                    arrow.move(to: p)
                    arrow.addLine(
                        to: CGPoint(
                            x: p.x + dirX / len * 14,
                            y: p.y + dirZ / len * 14
                        )
                    )
                    context.stroke(
                        arrow,
                        with: .color(color),
                        lineWidth: 1
                    )
                }
            }
        }
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#if os(iOS)
/// Loads a preview HEIC lazily for the evidence gallery. Previews are
/// derived convenience artifacts; a missing/unreadable preview degrades
/// to a placeholder, never to a hidden failure.
private struct AsyncPreviewImage: View {
    let url: URL

    var body: some View {
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Text("Preview unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
