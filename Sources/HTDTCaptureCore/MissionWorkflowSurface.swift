import Foundation

/// The advanced workflows shipped under the production root (issue
/// legacy bolph71656-ai/HTDT-Capture#353): each surface must be reachable from `CaptureRootView`
/// through ordinary navigation — never through test-only
/// construction.
public enum MissionWorkflowSurface: String, Codable, Sendable,
    CaseIterable, Equatable
{
    /// Imported capture task plan checklist (legacy bolph71656-ai/HTDT-Capture#240).
    case taskPlanChecklist = "task_plan_checklist"
    /// Connected multi-region capture segments/portals (legacy bolph71656-ai/HTDT-Capture#222).
    case connectedSpace = "connected_space"
    /// Plan-vs-capture as-built verification (legacy bolph71656-ai/HTDT-Capture#293).
    case asBuiltVerification = "as_built_verification"
    /// Post-scan authoring: annotations, measurements, evidence
    /// (the annotation workspace).
    case postScanAuthoring = "post_scan_authoring"
    /// External measurement instrument import (legacy bolph71656-ai/HTDT-Capture#226/legacy bolph71656-ai/HTDT-Capture#355).
    case instrumentImport = "instrument_import"
    /// HTDT repair/follow-up tasks returned to Capture (legacy bolph71656-ai/HTDT-Capture#321).
    case repairTasks = "repair_tasks"
}

/// Whether a surface is enterable right now from the production root.
public enum MissionWorkflowAvailability: String, Codable, Sendable,
    Equatable
{
    /// Enterable now.
    case ready
    /// Present in the workflow list but blocked on a missing
    /// prerequisite (e.g. no live coordinate authority); the entry
    /// explains what is needed rather than hiding the work entirely.
    case blocked
    /// Not part of this context at all — not listed.
    case hidden
}

/// One entry the production root lists for the operator.
public struct MissionWorkflowEntry: Sendable, Equatable {
    public let surface: MissionWorkflowSurface
    public let availability: MissionWorkflowAvailability
    /// Short operator-facing reason/detail (e.g. pending count).
    public let detail: String?

    public init(
        surface: MissionWorkflowSurface,
        availability: MissionWorkflowAvailability,
        detail: String? = nil
    ) {
        self.surface = surface
        self.availability = availability
        self.detail = detail
    }
}

/// The captured context the router evaluates. Pure facts the host
/// already owns — no view state — so reachability is verifiable
/// without constructing SwiftUI.
public struct MissionWorkflowContext: Sendable, Equatable {
    /// A capture task plan was imported and is loaded.
    public var taskPlanLoaded: Bool
    /// The operator declared a multi-region connected mission before
    /// acquisition (legacy bolph71656-ai/HTDT-Capture#353: connected controls appear only when the
    /// mission requires them).
    public var connectedSpaceIntent: Bool
    /// A connected-space tracker exists (segments already recorded).
    public var connectedSpaceActive: Bool
    /// An as-built plan was imported (planned specs present).
    public var asBuiltPlanLoaded: Bool
    /// The live working revision's coordinate authority is still
    /// usable for spatial work (bound space, not sealed).
    public var spatialAuthorityLive: Bool
    /// A live working revision exists (scanning through review).
    public var captureInProgress: Bool
    /// The annotation workspace can be entered now (Review).
    public var annotationWorkspaceEnterable: Bool
    /// Unresolved repair tasks exist for the current context.
    public var unresolvedRepairTasks: Int

    public init(
        taskPlanLoaded: Bool = false,
        connectedSpaceIntent: Bool = false,
        connectedSpaceActive: Bool = false,
        asBuiltPlanLoaded: Bool = false,
        spatialAuthorityLive: Bool = false,
        captureInProgress: Bool = false,
        annotationWorkspaceEnterable: Bool = false,
        unresolvedRepairTasks: Int = 0
    ) {
        self.taskPlanLoaded = taskPlanLoaded
        self.connectedSpaceIntent = connectedSpaceIntent
        self.connectedSpaceActive = connectedSpaceActive
        self.asBuiltPlanLoaded = asBuiltPlanLoaded
        self.spatialAuthorityLive = spatialAuthorityLive
        self.captureInProgress = captureInProgress
        self.annotationWorkspaceEnterable =
            annotationWorkspaceEnterable
        self.unresolvedRepairTasks = unresolvedRepairTasks
    }
}

/// Decides which advanced workflows the production root surfaces and
/// whether each is enterable right now (issue bolph71656-ai/HTDT-Capture#353). The router is
/// the single source of truth for reachability: the view lists
/// exactly these entries and the reachability test asserts on them.
public enum MissionWorkflowRouter {
    /// Ordered entries for the current context. Hidden surfaces are
    /// omitted so a simple single-room capture is never burdened with
    /// controls its mission does not need.
    public static func entries(
        for context: MissionWorkflowContext
    ) -> [MissionWorkflowEntry] {
        var entries: [MissionWorkflowEntry] = []

        if context.taskPlanLoaded {
            entries.append(
                MissionWorkflowEntry(
                    surface: .taskPlanChecklist,
                    availability: .ready
                )
            )
        }

        if context.connectedSpaceIntent || context.connectedSpaceActive {
            entries.append(
                MissionWorkflowEntry(
                    surface: .connectedSpace,
                    availability: context.spatialAuthorityLive
                        ? .ready
                        : .blocked,
                    detail: context.spatialAuthorityLive
                        ? nil
                        : "Requires a live capture coordinate space"
                )
            )
        }

        if context.asBuiltPlanLoaded {
            entries.append(
                MissionWorkflowEntry(
                    surface: .asBuiltVerification,
                    availability: context.spatialAuthorityLive
                        ? .ready
                        : .blocked,
                    detail: context.spatialAuthorityLive
                        ? nil
                        : "Requires a live capture coordinate space"
                )
            )
        }

        if context.captureInProgress {
            entries.append(
                MissionWorkflowEntry(
                    surface: .postScanAuthoring,
                    availability: context.annotationWorkspaceEnterable
                        ? .ready
                        : .blocked,
                    detail: context.annotationWorkspaceEnterable
                        ? nil
                        : "Available once the scan is reviewed"
                )
            )
            entries.append(
                MissionWorkflowEntry(
                    surface: .instrumentImport,
                    availability: context.annotationWorkspaceEnterable
                        ? .ready
                        : .blocked,
                    detail: context.annotationWorkspaceEnterable
                        ? nil
                        : "Available once the scan is reviewed"
                )
            )
        }

        if context.unresolvedRepairTasks > 0 {
            entries.append(
                MissionWorkflowEntry(
                    surface: .repairTasks,
                    availability: .ready,
                    detail: String(context.unresolvedRepairTasks)
                )
            )
        }

        return entries
    }

    /// Every surface currently enterable from the production root.
    public static func reachableSurfaces(
        for context: MissionWorkflowContext
    ) -> Set<MissionWorkflowSurface> {
        Set(
            entries(for: context)
                .filter { $0.availability == .ready }
                .map(\.surface)
        )
    }
}
