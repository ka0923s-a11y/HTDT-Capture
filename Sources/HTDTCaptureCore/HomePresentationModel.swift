import Foundation

/// Home information architecture v2 (issue #406): the presentation
/// model for the landing surface. The view binds three bounded
/// primary intents — Work, Library, Send & connections — and this
/// model decides what the landing answers first: *what should I do
/// next?*
///
/// Priority order (issue §3): recoverable work → mission action →
/// new capture → recent artifact → actionable delivery → admin
/// (always hidden unless actionable). Every badge counts only
/// actionable items; healthy subsystems stay quiet.
public enum CaptureHomeIntent: String, Sendable, CaseIterable {
    /// The work queue: resume drafts, missions, pending deliveries
    /// that need the operator.
    case work
    /// Content-first library: series → revisions, scoped search.
    case library
    /// Destinations, delivery queue, receipts — secondary while
    /// healthy.
    case sendConnections = "send_connections"
}

// MARK: - Next action

/// The one dominant answer the landing gives (issue #406 §3).
public enum HomeNextAction: Sendable, Equatable {
    /// A recovered working revision can be reopened.
    case resumeDraft(RecoverableWorkingRevision)
    /// The active mission resumes (lifecycle `in_progress`).
    case continueMission(HTDTMissionRecord)
    /// A mission is ready to start.
    case startMission(HTDTMissionRecord)
    /// Nothing pending — begin a new capture.
    case newCapture
    /// Nothing pending and capture unavailable — open the most
    /// recent artifact instead.
    case openRecentArtifact(CaptureRevisionID)
    /// A delivery job needs an operator decision (failed/blocked/
    /// rejected/paused).
    case retryDelivery(HTDTDeliveryJob)
    /// Nothing to surface — the landing stays quiet.
    case none
}

/// One row of the Work queue (issue #406 §4): everything on it is
/// actionable — informational items do not appear.
public struct HomeWorkItem: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case resumeDraft = "resume_draft"
        case continueMission = "continue_mission"
        case startMission = "start_mission"
        case missionFollowUp = "mission_follow_up"
        case retryDelivery = "retry_delivery"
        case reviewArtifact = "review_artifact"
    }

    /// Secondary-line value the model emits when a startable mission's
    /// dependencies are unmet. The view compares against it to pick the
    /// matching localized subtitle — keeping the only lifecycle
    /// distinction the row needs inside the model.
    public static let blockedMissionSubtitle = "Mission — dependencies unmet"

    public let kind: Kind
    /// Stable row identity — draft URL, mission record id, job id or
    /// revision id string.
    public let identity: String
    public let title: String
    /// Secondary line — progress, reason, or provenance.
    public let subtitle: String?

    public init(
        kind: Kind,
        identity: String,
        title: String,
        subtitle: String? = nil
    ) {
        self.kind = kind
        self.identity = identity
        self.title = title
        self.subtitle = subtitle
    }

    public var id: String { kind.rawValue + ":" + identity }
}

// MARK: - Attention badges

/// One readiness problem worth an operator decision (issue #406 §5):
/// contextual — hidden entirely when everything is normal.
public struct HomeReadinessAttention:
    Sendable, Equatable, Identifiable
{
    public enum Kind: String, Sendable {
        case cameraPermissionDenied = "camera_permission_denied"
        case spatialCaptureUnavailable = "spatial_capture_unavailable"
        case other
    }

    public let kind: Kind
    public let label: String

    public init(kind: Kind, label: String) {
        self.kind = kind
        self.label = label
    }

    public var id: String { kind.rawValue }
}

/// Maintenance counts (issue #406 §5): quarantined artifacts,
/// working orphans and enumeration failures. The admin row appears
/// only when `attentionCount > 0` — badges count actionable items
/// only.
public struct HomeMaintenanceSummary: Sendable, Equatable {
    public let quarantinedArtifactCount: Int
    public let workingOrphanCount: Int
    public let enumerationFailureCount: Int

    public init(
        quarantinedArtifactCount: Int = 0,
        workingOrphanCount: Int = 0,
        enumerationFailureCount: Int = 0
    ) {
        self.quarantinedArtifactCount = quarantinedArtifactCount
        self.workingOrphanCount = workingOrphanCount
        self.enumerationFailureCount = enumerationFailureCount
    }

    public var attentionCount: Int {
        quarantinedArtifactCount + workingOrphanCount
            + enumerationFailureCount
    }

    public var needsAttention: Bool { attentionCount > 0 }
}

/// Delivery health (issue #406 §6): jobs are split into in-flight
/// (healthy, quiet) and actionable (operator decision needed).
/// Destinations stay a secondary destination row while healthy.
public struct HomeSendSummary: Sendable, Equatable {
    /// queued/sending/retryWait — moving on their own.
    public let inFlightJobs: [HTDTDeliveryJob]
    /// failed/blocked/rejected/paused — the only delivery items a
    /// badge may count.
    public let actionableJobs: [HTDTDeliveryJob]
    /// deliveredStaged/cancelled — history, not work.
    public let completedJobs: [HTDTDeliveryJob]
    public let pairedDestinationCount: Int

    public init(
        deliveryJobs: [HTDTDeliveryJob],
        pairedDestinationCount: Int
    ) {
        var inFlight: [HTDTDeliveryJob] = []
        var actionable: [HTDTDeliveryJob] = []
        var completed: [HTDTDeliveryJob] = []
        for job in deliveryJobs {
            switch job.state {
            case .queued, .sending, .retryWait:
                inFlight.append(job)
            case .paused, .blocked, .failed, .rejected:
                actionable.append(job)
            case .deliveredStaged, .cancelled:
                completed.append(job)
            }
        }
        self.inFlightJobs = inFlight
        self.actionableJobs = actionable
        self.completedJobs = completed
        self.pairedDestinationCount = pairedDestinationCount
    }

    public var actionableCount: Int { actionableJobs.count }
}

// MARK: - The model

/// Derived home content — computed from app state, never persisted.
/// The view renders it; nothing here imports SwiftUI or reaches
/// into the capture state machine.
public struct CaptureHomeModel: Sendable, Equatable {
    public let nextAction: HomeNextAction
    /// Work queue rows — every one actionable.
    public let workItems: [HomeWorkItem]
    public let send: HomeSendSummary
    public let maintenance: HomeMaintenanceSummary
    public let readinessAttentions: [HomeReadinessAttention]
    /// Library summary for the content-first section header —
    /// counts only; the view owns grouping/search.
    public let libraryCaptureCount: Int
    public let librarySeriesCount: Int
    /// Most recent finalized revision (candidate for the
    /// recent-artifact row).
    public let mostRecentRevisionID: CaptureRevisionID?
    /// Active missions that still have work on device —
    /// `in_progress` records lead, startable ones follow, and
    /// `needs_follow_up` closes the list.
    public let actionableMissions: [HTDTMissionRecord]

    public init(
        recoverableDrafts: [RecoverableWorkingRevision],
        missions: [HTDTMissionRecord],
        activeMissionRecordID: String?,
        deliveryJobs: [HTDTDeliveryJob],
        pairedDestinationCount: Int,
        libraryCaptureCount: Int,
        librarySeriesCount: Int,
        mostRecentRevisionID: CaptureRevisionID?,
        maintenance: HomeMaintenanceSummary,
        readinessAttentions: [HomeReadinessAttention],
        captureAvailable: Bool
    ) {
        self.send = HomeSendSummary(
            deliveryJobs: deliveryJobs,
            pairedDestinationCount: pairedDestinationCount
        )
        self.maintenance = maintenance
        self.readinessAttentions = readinessAttentions
        self.libraryCaptureCount = libraryCaptureCount
        self.librarySeriesCount = librarySeriesCount
        self.mostRecentRevisionID = mostRecentRevisionID

        // Missions are a work queue: actionable records only, in
        // decision order — resume what's running, then startable,
        // then receiver follow-ups.
        let active = missions.filter { $0.lifecycle == .inProgress }
            .sorted { lhs, rhs in
                lhs.recordID == activeMissionRecordID
                    && rhs.recordID != activeMissionRecordID
            }
        let startable = missions.filter {
            $0.lifecycle == .received || $0.lifecycle == .ready
                || $0.lifecycle == .blockedDependency
        }
        let followUps = missions.filter {
            $0.lifecycle == .needsFollowUp
        }
        self.actionableMissions = active + startable + followUps

        var items: [HomeWorkItem] = []
        for draft in recoverableDrafts {
            items.append(
                HomeWorkItem(
                    kind: .resumeDraft,
                    identity: draft.url.path,
                    title: "Resume draft",
                    subtitle: draft.revisionID.description
                )
            )
        }
        for record in active {
            items.append(
                HomeWorkItem(
                    kind: .continueMission,
                    identity: record.recordID,
                    title: record.purpose ?? record.missionID,
                    subtitle: "Mission in progress"
                )
            )
        }
        for record in startable {
            items.append(
                HomeWorkItem(
                    kind: .startMission,
                    identity: record.recordID,
                    title: record.purpose ?? record.missionID,
                    subtitle: record.lifecycle == .blockedDependency
                        ? HomeWorkItem.blockedMissionSubtitle
                        : "Mission ready"
                )
            )
        }
        for record in followUps {
            items.append(
                HomeWorkItem(
                    kind: .missionFollowUp,
                    identity: record.recordID,
                    title: record.purpose ?? record.missionID,
                    subtitle: "Receiver requested follow-up"
                )
            )
        }
        for job in send.actionableJobs {
            items.append(
                HomeWorkItem(
                    kind: .retryDelivery,
                    identity: job.deliveryJobID,
                    title: "Delivery needs attention",
                    subtitle: job.lastError
                )
            )
        }
        if let mostRecentRevisionID {
            items.append(
                HomeWorkItem(
                    kind: .reviewArtifact,
                    identity: mostRecentRevisionID.description,
                    title: "Review latest capture",
                    subtitle: mostRecentRevisionID.description
                )
            )
        }
        self.workItems = items

        // The single dominant answer, in the issue's priority order.
        if let draft = recoverableDrafts.first {
            nextAction = .resumeDraft(draft)
        } else if let mission = active.first {
            nextAction = .continueMission(mission)
        } else if let mission = startable.first {
            nextAction = .startMission(mission)
        } else if captureAvailable {
            nextAction = .newCapture
        } else if let mostRecentRevisionID {
            nextAction = .openRecentArtifact(mostRecentRevisionID)
        } else if let job = send.actionableJobs.first {
            nextAction = .retryDelivery(job)
        } else {
            nextAction = .none
        }
    }
}
