import Foundation
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
    public let scanningPreview: AnyView?
    public let scanCoverage: ScanCoverageSummary
    public let observationStability: ObservationStabilitySummary
    public let derivedShapePreview: DerivedShapePreviewSnapshot
    public let scanEvidenceFrameCount: Int
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
        scanningPreview: AnyView? = nil,
        scanCoverage: ScanCoverageSummary = .empty,
        observationStability: ObservationStabilitySummary = .empty,
        derivedShapePreview: DerivedShapePreviewSnapshot = .empty,
        scanEvidenceFrameCount: Int = 0,
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
        self.scanningPreview = scanningPreview
        self.scanCoverage = scanCoverage
        self.observationStability = observationStability
        self.derivedShapePreview = derivedShapePreview
        self.scanEvidenceFrameCount = scanEvidenceFrameCount
        self.actions = actions
    }

    public var body: some View {
        Group {
            if state == .scanning,
               let scanningPreview
            {
                CaptureScanningView(
                    preview: scanningPreview,
                    coverage: scanCoverage,
                    observation: observationStability,
                    derivedPreview: derivedShapePreview,
                    evidenceFrameCount: scanEvidenceFrameCount,
                    captureEvidenceFrame:
                        actions.captureEvidenceFrame,
                    endScan: actions.beginReview
                )
            } else {
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
                    LabeledContent(
                        "State",
                        value: localizedState(state)
                    )
                    if let cameraPermission {
                        LabeledContent(
                            "Camera permission",
                            value: localizedPermission(
                                cameraPermission
                            )
                        )
                    }
                    if let workingSetStatus {
                        LabeledContent(
                            "Working set",
                            value: workingSetStatus
                        )
                    }
                    if let lastFailure {
                        LabeledContent(
                            "Failure",
                            value: localizedFailure(lastFailure)
                        )
                    }
                }

                Section("Capabilities") {
                    LabeledContent(
                        "RoomPlan + mesh",
                        value: localizedAvailability(
                            capabilities.roomPlanMeshEligible
                        )
                    )
                    LabeledContent(
                        "Scene depth",
                        value: localizedAvailability(
                            capabilities.sceneDepthSupported
                        )
                    )
                    if capabilities.requiresCombinedFeatureProbe {
                        Text(
                            "Combined RoomPlan/depth behavior still requires physical-device verification."
                        )
                    }
                }

                Section("Controls") {
                    controls
                }

                if state == .failed,
                   let lastFailure
                {
                    Section("Recovery") {
                        Text(
                            failureReasonText(lastFailure)
                        )
                        .font(.headline)

                        Text(
                            failureRecoveryText(lastFailure)
                        )
                        .foregroundStyle(.secondary)
                    }
                }

                if state == .reviewing,
                   let qualityReport
                {
                    Section("Quality") {
                        LabeledContent(
                            "HTDT ingestion",
                            value: localizedReadiness(
                                qualityReport.readyForHTDTIngestion
                            )
                        )
                        LabeledContent(
                            "Integrity preflight",
                            value: localizedIntegrity(
                                qualityReport.integrityStatus
                            )
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
                            value: localizedPassFail(
                                validationReport.valid
                            )
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
                "The host app does not enter a pseudo-paused RoomPlan state. Ending RoomPlan creates a scan boundary."
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
            Button(
                "Discard failed capture",
                role: .destructive,
                action: actions.resetCapture
            )

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

    private func progressRow(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text)
        }
    }

    private func localizedState(_ state: CaptureState) -> String {
        switch state {
        case .idle:
            return String(localized: "Idle")
        case .capabilityCheck:
            return String(localized: "Checking capabilities")
        case .permissions:
            return String(localized: "Requesting permissions")
        case .preparing:
            return String(localized: "Preparing")
        case .scanning:
            return String(localized: "Scanning")
        case .paused:
            return String(localized: "Paused")
        case .reviewing:
            return String(localized: "Reviewing")
        case .annotating:
            return String(localized: "Annotating")
        case .validating:
            return String(localized: "Validating")
        case .finalized:
            return String(localized: "Finalized")
        case .exported:
            return String(localized: "Exported")
        case .failed:
            return String(localized: "Failed")
        }
    }

    private func localizedPermission(
        _ status: CameraPermissionStatus
    ) -> String {
        switch status {
        case .notDetermined:
            return String(localized: "Not determined")
        case .authorized:
            return String(localized: "Authorized")
        case .denied:
            return String(localized: "Denied")
        case .restricted:
            return String(localized: "Restricted")
        case .unavailable:
            return String(localized: "Unavailable")
        }
    }

    private func localizedFailure(_ failure: CaptureFailureCode) -> String {
        switch failure {
        case .permissionDenied:
            return String(localized: "Permission denied")
        case .unsupportedDevice:
            return String(localized: "Unsupported device")
        case .trackingUnavailable:
            return String(localized: "Tracking unavailable")
        case .roomPlanFailure:
            return String(localized: "RoomPlan failure")
        case .storagePressure:
            return String(localized: "Storage pressure")
        case .persistenceFailure:
            return String(localized: "Persistence failure")
        case .thermalPressure:
            return String(localized: "Thermal pressure")
        case .interrupted:
            return String(localized: "Interrupted")
        case .unknown:
            return String(localized: "Unknown error")
        }
    }

    private func failureReasonText(
        _ failure: CaptureFailureCode
    ) -> String {
        switch failure {
        case .interrupted:
            return String(
                localized:
                    "The app left the foreground during an active capture. HTDT no longer assumes the same AR coordinate space is valid."
            )
        case .trackingUnavailable:
            return String(
                localized:
                    "AR tracking or the current camera frame became unavailable during capture."
            )
        case .roomPlanFailure:
            return String(
                localized:
                    "RoomPlan could not start or continue the room scan reliably."
            )
        case .storagePressure:
            return String(
                localized:
                    "Available storage fell below the safe capture threshold."
            )
        case .thermalPressure:
            return String(
                localized:
                    "The device reached a critical thermal state during capture."
            )
        case .persistenceFailure:
            return String(
                localized:
                    "Required capture evidence could not be written safely."
            )
        case .permissionDenied:
            return String(
                localized:
                    "Camera access is required to capture RoomPlan and AR evidence."
            )
        case .unsupportedDevice:
            return String(
                localized:
                    "This device does not provide the required RoomPlan and mesh capture capabilities."
            )
        case .unknown:
            return String(
                localized:
                    "The capture stopped because of an unexpected error."
            )
        }
    }

    private func failureRecoveryText(
        _ failure: CaptureFailureCode
    ) -> String {
        switch failure {
        case .interrupted:
            return String(
                localized:
                    "This scan is not silently resumed. Discard the failed capture and start a new scan so a fresh coordinate-space authority is created."
            )
        case .trackingUnavailable:
            return String(
                localized:
                    "Move to a well-lit area with visible room features, then discard this failed capture and start a new scan."
            )
        case .roomPlanFailure:
            return String(
                localized:
                    "Discard this failed capture and start again. Move slowly and keep walls, corners, and furniture edges in view."
            )
        case .storagePressure:
            return String(
                localized:
                    "Free device storage before starting another capture."
            )
        case .thermalPressure:
            return String(
                localized:
                    "Let the device cool before starting another capture."
            )
        case .persistenceFailure:
            return String(
                localized:
                    "Check free storage and retry with a new capture. HTDT does not continue when canonical evidence persistence is uncertain."
            )
        case .permissionDenied:
            return String(
                localized:
                    "Allow camera access in iOS Settings, then start a new capture."
            )
        case .unsupportedDevice:
            return String(
                localized:
                    "Use a supported LiDAR-capable iPhone or iPad for this capture workflow."
            )
        case .unknown:
            return String(
                localized:
                    "Discard the failed capture and retry. If the error repeats, record the screen state before resetting."
            )
        }
    }

    private func localizedAvailability(_ available: Bool) -> String {
        available
            ? String(localized: "Available")
            : String(localized: "Unavailable")
    }

    private func localizedReadiness(_ ready: Bool) -> String {
        ready
            ? String(localized: "Ready")
            : String(localized: "Not ready")
    }

    private func localizedPassFail(_ pass: Bool) -> String {
        pass
            ? String(localized: "Pass")
            : String(localized: "Fail")
    }

    private func localizedIntegrity(
        _ status: BundleIntegrityStatus
    ) -> String {
        switch status {
        case .notChecked:
            return String(localized: "Not checked")
        case .pass:
            return String(localized: "Pass")
        case .fail:
            return String(localized: "Fail")
        }
    }
}
