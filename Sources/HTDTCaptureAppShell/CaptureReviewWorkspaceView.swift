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
    /// #232: confirms a field/install datum derived from the
    /// committed room reference frame. Returns false when the room
    /// frame is missing or the commit failed.
    public let confirmFieldDatumFromRoomFrame:
        () async -> Bool
    /// #232: removes the committed field datum payload.
    public let removeRoomFieldDatum: () async -> Void
    /// #231: captures the camera position as the center for a
    /// user-declared opening candidate.
    public let captureOpeningCenter: () -> Void
    /// Clears a pending opening-center capture so another candidate
    /// can be marked.
    public let clearOpeningCenter: () -> Void
    /// Pending center point for a user-declared opening candidate.
    public let openingCenterPending: WorldPoint3D?

    @State private var openings: [RoomOpeningCandidate]?
    @State private var openingSaveState: String?
    @State private var confirmingFrameRemoval:
        EvidenceFrameID?
    @State private var newOpeningKind: RoomOpeningKind = .hvacGrille
    @State private var newOpeningState: RoomOpeningState = .open
    @State private var newOpeningWidth = "0.30"
    @State private var newOpeningHeight = "0.30"

    public init(
        model: CaptureReviewWorkspaceModel,
        roomFrameOriginPending: WorldPoint3D? = nil,
        openingCenterPending: WorldPoint3D? = nil,
        removeEvidenceFrame: @escaping
            (EvidenceFrameID) async -> Void = { _ in },
        openingReviewCandidates: @escaping
            () async -> [RoomOpeningCandidate]? = { nil },
        commitOpeningReview: @escaping
            ([RoomOpeningCandidate]) async -> Bool = { _ in false },
        captureRoomFrameOrigin: @escaping () -> Void = {},
        confirmRoomReferenceFrame: @escaping () -> Void = {},
        confirmFieldDatumFromRoomFrame: @escaping
            () async -> Bool = { false },
        removeRoomFieldDatum: @escaping () async -> Void = {},
        captureOpeningCenter: @escaping () -> Void = {},
        clearOpeningCenter: @escaping () -> Void = {}
    ) {
        self.model = model
        self.roomFrameOriginPending = roomFrameOriginPending
        self.openingCenterPending = openingCenterPending
        self.removeEvidenceFrame = removeEvidenceFrame
        self.openingReviewCandidates = openingReviewCandidates
        self.commitOpeningReview = commitOpeningReview
        self.captureRoomFrameOrigin = captureRoomFrameOrigin
        self.confirmRoomReferenceFrame = confirmRoomReferenceFrame
        self.confirmFieldDatumFromRoomFrame =
            confirmFieldDatumFromRoomFrame
        self.removeRoomFieldDatum = removeRoomFieldDatum
        self.captureOpeningCenter = captureOpeningCenter
        self.clearOpeningCenter = clearOpeningCenter
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
                            Text(entityType + " · " + entityID)
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
                        LabeledContent(
                            measurement.quantityType,
                            value: measurement.measurementID
                                .description
                        )
                        .font(.caption)
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
                    // User-declared boundary openings (issue #231):
                    // vents, grilles, undercuts, and penetrations
                    // RoomPlan never infers. A captured camera point
                    // supplies the center; these never promote into
                    // solver Portal physics automatically.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add opening candidate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker(
                            "Kind",
                            selection: $newOpeningKind
                        ) {
                            ForEach(
                                RoomOpeningKind.allCases,
                                id: \.self
                            ) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker(
                            "State",
                            selection: $newOpeningState
                        ) {
                            ForEach(
                                RoomOpeningState.allCases,
                                id: \.self
                            ) { state in
                                Text(state.rawValue).tag(state)
                            }
                        }
                        .pickerStyle(.segmented)
                        HStack(spacing: 8) {
                            TextField(
                                "Width m",
                                text: $newOpeningWidth
                            )
                            TextField(
                                "Height m",
                                text: $newOpeningHeight
                            )
                        }
                        .font(.caption)
                        Button(
                            openingCenterPending == nil
                                ? "Mark opening center"
                                : "Center captured"
                        ) {
                            captureOpeningCenter()
                        }
                        .disabled(openingCenterPending != nil)
                        if let center = openingCenterPending {
                            Button("Add candidate") {
                                addUserOpeningCandidate(
                                    center: center
                                )
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

            Section("Field datum (HTDT promotion)") {
                if let datum = model.roomFieldDatum {
                    LabeledContent(
                        "Origin",
                        value: datum.origin.kind.rawValue
                    )
                    LabeledContent(
                        "Axis",
                        value: datum.axis.kind.rawValue
                    )
                    LabeledContent(
                        "Vertical datum",
                        value: datum.verticalDatum.kind
                            .rawValue
                    )
                    LabeledContent(
                        "Origin (m)",
                        value: String(
                            format: "%.2f, %.2f, %.2f",
                            datum.fieldFromCaptureWorld
                                .originMeters.x,
                            datum.fieldFromCaptureWorld
                                .originMeters.y,
                            datum.fieldFromCaptureWorld
                                .originMeters.z
                        )
                    )
                    LabeledContent(
                        "Status",
                        value: {
                            switch model
                                .roomFieldDatumStaleness
                            {
                            case .current:
                                return "current"
                            case .stale(let refs):
                                return "stale — "
                                    + "\(refs.count)"
                                    + " unresolved ref(s)"
                            case nil:
                                return "current"
                            }
                        }()
                    )
                    Text(
                        "Promotion reference only: records the capture-world→field datum convention and its exact transform. It is not T_scene_from_capture_world."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if !model.readOnly
                        && !model.spatialCaptureSealed
                    {
                        Button(
                            "Remove field datum",
                            role: .destructive
                        ) {
                            Task {
                                await removeRoomFieldDatum()
                            }
                        }
                        .font(.caption)
                    }
                } else {
                    Text("No field datum confirmed")
                        .foregroundStyle(.secondary)
                    if !model.readOnly
                        && !model.spatialCaptureSealed
                    {
                        Button("Confirm from room frame") {
                            Task {
                                _ = await
                                    confirmFieldDatumFromRoomFrame()
                            }
                        }
                        .disabled(
                            model.roomReferenceFrame == nil
                        )
                        if model.roomReferenceFrame == nil {
                            Text(
                                "Confirm a room reference frame first."
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                    + " · "
                    + opening.openState.rawValue
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
                HStack(spacing: 8) {
                    Text("State")
                    Button("Open") {
                        setOpenState(.open, on: opening)
                    }
                    Button("Closed") {
                        setOpenState(.closed, on: opening)
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
        guard var current = openings
            ?? model.openingReview?.openings
        else { return }
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

    private func setOpenState(
        _ state: RoomOpeningState,
        on opening: RoomOpeningCandidate
    ) {
        guard var current = openings
            ?? model.openingReview?.openings
        else { return }
        current = OpeningReviewEditor.setOpenState(
            state,
            openingID: opening.openingID,
            in: current
        ) ?? current
        openings = current
    }

    private func addUserOpeningCandidate(
        center: WorldPoint3D
    ) {
        let width = Double(newOpeningWidth) ?? 0.3
        let height = Double(newOpeningHeight) ?? 0.3
        var current = openings
            ?? model.openingReview?.openings
            ?? []
        if let updated = OpeningReviewEditor
            .addUserDeclaredCandidate(
                kind: newOpeningKind,
                sourceRef: "user:"
                    + UUID()
                        .uuidString.lowercased(),
                centerMeters: center,
                widthMeters: width,
                heightMeters: height,
                openState: newOpeningState,
                evidenceRefs: [],
                to: current
            )
        {
            current = updated
            clearOpeningCenter()
        }
        openings = current
    }

    private func retentionLabel(
        _ reason: EvidenceRetentionReason
    ) -> String {
        switch reason {
        case .endBoundary:
            return "Closing evidence"
        case .linkedToAuthority:
            return "Referenced evidence"
        case .automaticKeyframe:
            return "Automatic keyframe"
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
