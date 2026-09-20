import SwiftUI
import HTDTCaptureCore
import HTDTCapturePlatform

public struct CaptureRootActions {
    public let beginCapture: () -> Void
    public let beginReview: () -> Void
    public let captureEvidenceFrame: () -> Void
    public let beginAnnotation: () -> Void
    public let captureRaycastPlacement:
        () async throws -> AnnotationPlacementAuthority
    public let captureSpeakerOrientation:
        () async throws -> AnnotationOrientationAuthority
    public let commitAnnotationAuthority: (
        [CaptureAnnotationEntity],
        [CaptureMeasurement]
    ) -> Void
    public let cancelAnnotation: () -> Void
    public let finalizeCapture: () -> Void
    public let prepareExport: () -> Void
    public let resetCapture: () -> Void

    public init(
        beginCapture: @escaping () -> Void = {},
        beginReview: @escaping () -> Void = {},
        captureEvidenceFrame: @escaping () -> Void = {},
        beginAnnotation: @escaping () -> Void = {},
        captureRaycastPlacement: @escaping
            () async throws -> AnnotationPlacementAuthority = {
                throw ManualAuthorityBuilderError.invalidPosition
            },
        captureSpeakerOrientation: @escaping
            () async throws -> AnnotationOrientationAuthority = {
                throw ManualAuthorityBuilderError.invalidSpeakerYaw
            },
        commitAnnotationAuthority: @escaping (
            [CaptureAnnotationEntity],
            [CaptureMeasurement]
        ) -> Void = { _, _ in },
        cancelAnnotation: @escaping () -> Void = {},
        finalizeCapture: @escaping () -> Void = {},
        prepareExport: @escaping () -> Void = {},
        resetCapture: @escaping () -> Void = {}
    ) {
        self.beginCapture = beginCapture
        self.beginReview = beginReview
        self.captureEvidenceFrame = captureEvidenceFrame
        self.beginAnnotation = beginAnnotation
        self.captureRaycastPlacement = captureRaycastPlacement
        self.captureSpeakerOrientation =
            captureSpeakerOrientation
        self.commitAnnotationAuthority =
            commitAnnotationAuthority
        self.cancelAnnotation = cancelAnnotation
        self.finalizeCapture = finalizeCapture
        self.prepareExport = prepareExport
        self.resetCapture = resetCapture
    }
}

public struct CaptureRootView: View {
    public let state: CaptureState
    public let capabilities: CaptureCapabilityMatrix
    public let cameraPermission: CameraPermissionStatus?
    public let lastFailure: CaptureFailureCode?
    public let workingSetStatus: String?
    public let qualityReport: CaptureQualityReport?
    public let validationReport: BundleValidationReport?
    public let exportURL: URL?
    public let annotationCoordinateSpaceID: CoordinateSpaceID?
    public let annotationEvidenceRefs: [String]
    public let annotationAuthorityCommitted: Bool
    public let actions: CaptureRootActions

    public init(
        state: CaptureState,
        capabilities: CaptureCapabilityMatrix,
        cameraPermission: CameraPermissionStatus? = nil,
        lastFailure: CaptureFailureCode? = nil,
        workingSetStatus: String? = nil,
        qualityReport: CaptureQualityReport? = nil,
        validationReport: BundleValidationReport? = nil,
        exportURL: URL? = nil,
        annotationCoordinateSpaceID: CoordinateSpaceID? = nil,
        annotationEvidenceRefs: [String] = [],
        annotationAuthorityCommitted: Bool = false,
        actions: CaptureRootActions = CaptureRootActions()
    ) {
        self.state = state
        self.capabilities = capabilities
        self.cameraPermission = cameraPermission
        self.lastFailure = lastFailure
        self.workingSetStatus = workingSetStatus
        self.qualityReport = qualityReport
        self.validationReport = validationReport
        self.exportURL = exportURL
        self.annotationCoordinateSpaceID =
            annotationCoordinateSpaceID
        self.annotationEvidenceRefs = annotationEvidenceRefs
        self.annotationAuthorityCommitted =
            annotationAuthorityCommitted
        self.actions = actions
    }

    public var body: some View {
        NavigationStack {
            if state == .annotating,
               let coordinateSpaceID =
                    annotationCoordinateSpaceID
            {
                CaptureAnnotationWorkspaceView(
                    coordinateSpaceID: coordinateSpaceID,
                    availableEvidenceRefs:
                        annotationEvidenceRefs,
                    captureRaycastPlacement:
                        actions.captureRaycastPlacement,
                    captureSpeakerOrientation:
                        actions.captureSpeakerOrientation,
                    onCommit:
                        actions.commitAnnotationAuthority,
                    onCancel: actions.cancelAnnotation
                )
                .navigationTitle("Capture authority")
            } else {
                List {
                Section("Capture") {
                    LabeledContent("State", value: state.rawValue)
                    if let cameraPermission {
                        LabeledContent(
                            "Camera permission",
                            value: cameraPermission.rawValue
                        )
                    }
                    if let workingSetStatus {
                        LabeledContent(
                            "Working set",
                            value: workingSetStatus
                        )
                    }
                    if let lastFailure {
                        LabeledContent("Failure", value: lastFailure.rawValue)
                    }
                }

                Section("Capabilities") {
                    LabeledContent(
                        "RoomPlan + mesh",
                        value: capabilities.roomPlanMeshEligible
                            ? "Available"
                            : "Unavailable"
                    )
                    LabeledContent(
                        "Scene depth",
                        value: capabilities.sceneDepthSupported
                            ? "Available"
                            : "Unavailable"
                    )
                    if capabilities.requiresCombinedFeatureProbe {
                        Text(
                            "Combined RoomPlan/depth behavior still requires "
                            + "physical-device verification."
                        )
                    }
                }

                Section("Controls") {
                    controls
                }

                if state == .reviewing,
                   let qualityReport
                {
                    Section("Quality") {
                        LabeledContent(
                            "HTDT ingestion",
                            value: qualityReport.readyForHTDTIngestion
                                ? "Ready"
                                : "Not ready"
                        )
                        LabeledContent(
                            "Integrity preflight",
                            value: qualityReport.integrityStatus.rawValue
                        )
                        NavigationLink("Review diagnostics") {
                            CaptureReviewView(
                                quality: qualityReport
                            )
                        }
                    }
                }

                if (state == .finalized || state == .exported),
                   let qualityReport,
                   let validationReport
                {
                    Section("Finalized bundle") {
                        LabeledContent(
                            "Validator",
                            value: validationReport.valid
                                ? "Pass"
                                : "Fail"
                        )
                        Text(validationReport.bundleDigest.description)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        NavigationLink("Review finalized capture") {
                            CaptureReviewView(
                                quality: qualityReport,
                                validation: validationReport
                            )
                        }
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label(
                                    "Share .htdtcapture",
                                    systemImage: "square.and.arrow.up"
                                )
                            }
                        }
                    }
                }
            }
                .navigationTitle("HTDT Capture")
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch state {
        case .idle:
            Button("Start capture", action: actions.beginCapture)
                .disabled(!capabilities.roomPlanMeshEligible)

        case .capabilityCheck:
            progressRow("Checking device capabilities…")

        case .permissions:
            progressRow("Requesting camera permission…")

        case .preparing:
            progressRow("Preparing capture working set…")

        case .scanning:
            Button(
                "Capture evidence frame",
                action: actions.captureEvidenceFrame
            )
            Button("End scan and review", action: actions.beginReview)

        case .paused:
            Text(
                "The host app does not enter a pseudo-paused RoomPlan state. "
                + "Ending RoomPlan creates a scan boundary."
            )

        case .reviewing:
            if !annotationAuthorityCommitted,
               annotationCoordinateSpaceID != nil
            {
                Button(
                    "Add annotations & measurements",
                    action: actions.beginAnnotation
                )
            } else if annotationAuthorityCommitted {
                Text("Annotation authority saved.")
            }

            if let qualityReport {
                Button(
                    "Validate and finalize",
                    action: actions.finalizeCapture
                )
                .disabled(
                    !qualityReport.readyForHTDTIngestion
                    || qualityReport.integrityStatus != .pass
                )
            } else {
                progressRow("Waiting for persisted evidence…")
            }

        case .failed:
            Button("Reset capture", action: actions.resetCapture)

        case .annotating:
            EmptyView()

        case .validating:
            progressRow("Validating and finalizing capture…")

        case .finalized:
            Button(
                "Prepare .htdtcapture",
                action: actions.prepareExport
            )

        case .exported:
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Validated .htdtcapture archive is ready to share."
                )
                Button(
                    "Start new capture",
                    action: actions.resetCapture
                )
            }
        }
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text)
        }
    }
}
