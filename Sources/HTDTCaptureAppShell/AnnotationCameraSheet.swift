import Foundation
import SwiftUI
import HTDTCaptureCore

/// What the camera sheet is capturing (#214).
public enum AnnotationCameraCaptureMode: Sendable {
    /// Center-reticle placement: probe + capture a position authority.
    case position
    /// Speaker heading: live yaw arrow + capture an orientation
    /// authority.
    case heading
}

/// Camera-first annotation capture sheet (#214/#246). The shared live
/// AR view is injected by the host — this view never creates a second
/// session — and overlays a center reticle whose feedback label reports
/// exactly what the center ray would hit (target class + distance)
/// before the operator commits a capture.
///
/// Placement captures return an `AnnotationPlacementAuthority`
/// carrying `mesh_hit_test` / `roomplan_binding` / `raycast`
/// provenance depending on the selected target preference; the
/// resolved class is shown again on the confirm step so an
/// estimated-plane fallback is never silent.
public struct AnnotationCameraCaptureSheet: View {
    public let mode: AnnotationCameraCaptureMode
    /// The shared live AR preview (RoomPlan capture view reusing the
    /// running ARSession). nil on platforms without one — the sheet
    /// then reports "camera unavailable" instead of hanging.
    public let cameraPreview: AnyView?
    /// Pollable probe for the current reticle; polls ~3x/second.
    public let probePlacementTarget:
        () async -> AnnotationPlacementProbe
    /// Pollable current camera heading in degrees (heading mode).
    public let probeCameraHeading: () async -> Float?
    /// Captures the placement authority for the requested target
    /// preference; nil result means "no hit" (non-destructive).
    public let capturePlacement: (
        PlacementTargetPreference
    ) async throws -> AnnotationPlacementAuthority?
    /// Captures the orientation authority (heading mode).
    public let captureOrientation:
        () async throws -> AnnotationOrientationAuthority
    /// RoomPlan objects the operator can bind to directly without
    /// aiming the reticle at one (#246).
    public let roomPlanObjects: [RoomPlanBindableObject]
    public let coordinateSpaceID: CoordinateSpaceID
    /// Delivers the accepted authority: `.placement` carries the provenance.
    public let onAccept: (
        AnnotationCameraCaptureResult
    ) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preference: PlacementTargetPreference =
        .automatic
    @State private var probe = AnnotationPlacementProbe.unavailable
    @State private var liveHeading: Float?
    @State private var capturing = false
    @State private var errorText: String?
    /// The frozen capture awaiting Accept / Retake.
    @State private var pendingResult:
        AnnotationCameraCaptureResult?
    @State private var pendingSummary = ""
    @State private var probeTask: Task<Void, Never>?

    public init(
        mode: AnnotationCameraCaptureMode,
        cameraPreview: AnyView?,
        coordinateSpaceID: CoordinateSpaceID,
        probePlacementTarget: @escaping
            () async -> AnnotationPlacementProbe =
            { .unavailable },
        probeCameraHeading: @escaping
            () async -> Float? = { nil },
        capturePlacement: @escaping (
            PlacementTargetPreference
        ) async throws -> AnnotationPlacementAuthority? = { _ in
            nil
        },
        captureOrientation: @escaping
            () async throws -> AnnotationOrientationAuthority = {
                throw ManualAuthorityBuilderError.invalidSpeakerYaw
            },
        roomPlanObjects: [RoomPlanBindableObject] = [],
        onAccept: @escaping (AnnotationCameraCaptureResult) -> Void
    ) {
        self.mode = mode
        self.cameraPreview = cameraPreview
        self.coordinateSpaceID = coordinateSpaceID
        self.probePlacementTarget = probePlacementTarget
        self.probeCameraHeading = probeCameraHeading
        self.capturePlacement = capturePlacement
        self.captureOrientation = captureOrientation
        self.roomPlanObjects = roomPlanObjects
        self.onAccept = onAccept
    }

    public var body: some View {
        ZStack {
            if let cameraPreview {
                cameraPreview
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack {
                Spacer()
                if pendingResult == nil {
                    aimReadout
                }
            }

            VStack {
                Spacer()
                if pendingResult == nil {
                    reticle
                    Spacer()
                }
            }

            VStack {
                Spacer()
                bottomPanel
            }
        }
        .background(Color.black.opacity(0.4))
        .navigationTitle(
            mode == .position
                ? String(localized: "Place with camera")
                : String(localized: "Capture facing direction")
        )
        .inlineNavigationBarTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
            }
        }
        .onAppear { startProbing() }
        .onDisappear { probeTask?.cancel() }
    }

    // MARK: Overlay pieces

    @ViewBuilder
    private var reticle: some View {
        if mode == .position {
            ZStack {
                Circle()
                    .stroke(
                        probe.status == .hit
                            ? Color.green
                            : Color.orange,
                        lineWidth: 2
                    )
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 4, height: 4)
            }
        } else {
            // Heading mode: an arrow that rotates with the live camera
            // yaw so the operator sees where "forward" points.
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
                .rotationEffect(
                    .degrees(Double(liveHeading ?? 0))
                )
        }
    }

    @ViewBuilder
    private var aimReadout: some View {
        HStack(spacing: 8) {
            if mode == .position {
                Text(AnnotationPresentation.probeStatusText(probe))
            } else if let liveHeading {
                Text(String(format:
                    String(localized: "Heading %.0f°"),
                    Double(liveHeading)
                ))
            } else {
                Text(String(localized: "Camera unavailable"))
            }
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.top, 60)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 12) {
            if let pendingResult {
                confirmCard(pendingResult)
            } else {
                if mode == .position {
                    Picker(
                        String(localized: "Target"),
                        selection: $preference
                    ) {
                        Text(String(localized: "Auto"))
                            .tag(PlacementTargetPreference.automatic)
                        Text(String(localized: "Surface mesh"))
                            .tag(PlacementTargetPreference.mesh)
                        if !roomPlanObjects.isEmpty {
                            Text(String(localized: "Object"))
                                .tag(
                                    PlacementTargetPreference
                                        .roomPlanObject
                                )
                        }
                        Text(String(localized: "Plane"))
                            .tag(PlacementTargetPreference.plane)
                    }
                    .pickerStyle(.segmented)

                    Button {
                        capture()
                    } label: {
                        Label(
                            String(localized: "Capture position"),
                            systemImage: "scope"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        capturing || probe.status != .hit
                    )
                } else {
                    Text(
                        "Point the phone the way the speaker faces, then capture."
                    )
                    .font(.caption)
                    .multilineTextAlignment(.center)

                    Button {
                        capture()
                    } label: {
                        Label(
                            String(localized: "Capture heading"),
                            systemImage: "location.north"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(capturing || liveHeading == nil)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    /// Freeze card shown after a capture so the operator sees the exact
    /// authority class before it lands on the form (#214/#246).
    @ViewBuilder
    private func confirmCard(
        _ result: AnnotationCameraCaptureResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pendingSummary)
                .font(.subheadline)
                .multilineTextAlignment(.leading)

            HStack {
                Button(String(localized: "Retake")) {
                    self.pendingResult = nil
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(String(localized: "Accept")) {
                    onAccept(result)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Capture plumbing

    private func startProbing() {
        probeTask?.cancel()
        probeTask = Task { @MainActor in
            while !Task.isCancelled {
                if mode == .position {
                    probe = await probePlacementTarget()
                } else {
                    liveHeading = await probeCameraHeading()
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func capture() {
        guard !capturing else { return }
        capturing = true
        errorText = nil

        Task { @MainActor in
            defer { capturing = false }
            do {
                switch mode {
                case .position:
                    let authority =
                        try await capturePlacement(preference)
                    guard let authority else {
                        // No hit: actionable, non-destructive.
                        errorText = AnnotationPresentation
                            .probeStatusText(.noHit)
                        return
                    }
                    pendingResult = .placement(authority)
                    pendingSummary = placementSummary(authority)
                case .heading:
                    let authority =
                        try await captureOrientation()
                    pendingResult = .orientation(authority)
                    pendingSummary = headingSummary(authority)
                }
            } catch {
                errorText =
                    AnnotationPresentation.errorText(error)
            }
        }
    }

    private func placementSummary(
        _ authority: AnnotationPlacementAuthority
    ) -> String {
        var parts = [
            String(localized: "Captured via ")
                + AnnotationPresentation.placementMethodName(
                    authority.placement.method
                )
        ]
        let position =
            authority.worldFromAnnotation.translationWorld
        parts.append(
            String(format: "(%.2f, %.2f, %.2f) m",
                Double(position.x),
                Double(position.y),
                Double(position.z)
            )
        )
        if let objectID = authority.placement.sourceRoomPlanObjectID {
            parts.append(
                String(localized: "bound to object ")
                    + objectID
            )
        } else if let meshAnchor = authority.placement.sourceMeshAnchorID {
            parts.append(
                String(localized: "mesh anchor ")
                    + meshAnchor.uuidString.prefix(8)
            )
        }
        if let target = authority.placement.raycast?.targetType {
            parts.append(
                String(localized: "plane: ") + target
            )
        }
        return parts.joined(separator: "\n")
    }

    private func headingSummary(
        _ authority: AnnotationOrientationAuthority
    ) -> String {
        let front = authority.orientation.frontAxisLocal
        let yaw = atan2(
            Double(front.x),
            Double(-front.z)
        ) * 180 / .pi
        return String(format:
            String(localized: "Captured heading %.0f°"), yaw)
    }
}

/// The authority accepted from the camera sheet.
public enum AnnotationCameraCaptureResult: Sendable {
    case placement(AnnotationPlacementAuthority)
    case orientation(AnnotationOrientationAuthority)
}
