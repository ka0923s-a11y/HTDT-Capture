# Optional-Work Admission/Degradation Policy (legacy bolph71656-ai/HTDT-Capture#273)

Issue bolph71656-ai/HTDT-Capture#273 (parent legacy bolph71656-ai/HTDT-Capture#266). Goal: keep optional Vision / Core AI /
Foundation Models / reference-object / high-quality-visual work from
degrading authoritative RoomPlan/ARKit/depth/persistence on
iPhone 17 Pro — through a **small admission/degradation policy layered
on existing authorities**, not a generic job scheduler.

## 1. Existing authorities stay authoritative

| Authority | Owns |
|---|---|
| `CaptureResourceMonitor` (Platform) | thermal/storage/memory/background pressure signals and the `capture_resource_event` timeline |
| `SharedARSessionController` (Platform) | live shared AR session, rendering mitigation, tracking quality |
| `CaptureWorkingSetStore` (Core) | writer/persistence admission and backlog pressure |
| `OptionalWorkAdmissionPolicy` + `OptionalWorkAdmissionTracker` (Platform, **this document's addition**) | only optional-work admission/degradation decisions and a bounded in-flight ledger |

The policy adds no second monitor and no parallel resource state
machine. Thermal/storage semantics continue to come from the monitor;
this policy only decides whether optional work may start, defer,
suspend, or cancel.

## 2. The Stage 1 contract

```text
canStart(workload, phase, captureHealth) -> allow | defer | reject
```

`OptionalWorkAdmissionPolicy.decision(for:in:health:activeAssistOccupied:requestInFlight:)`
is the pure decision table. `OptionalWorkAdmissionTracker` adds the
smallest stateful surface around it:

- the single **active-assist slot** (at most one operator-requested
  assist at a time);
- each feature's **one-in-flight request bound** (the legacy bolph71656-ai/HTDT-Capture#275 convention
  — no second queue around a feature that already bounds itself);
- a **ticket** (`OptionalWorkAdmissionTicket`) that binds the
  admission's request generation so a superseded or ended request's
  result is stale-rejected at the feature's own boundary;
- a **bounded, transition-compacted decision log** plus per-workload
  outcome aggregates (the instrumentation half of the issue).

## 3. Workload classes

`OptionalWorkloadClass` — policy values, not a task DSL:

| Class | Content |
|---|---|
| `captureCritical` | AR lifecycle, depth/mesh/frame evidence, RoomPlan, canonical persistence/finalization — never gated |
| `activeAssist` | One operator-requested task that directly supports the current measurement/evidence step (targeted object pass, label scan, identity/field-evidence photos, high-res frame evidence, source-quality preflight) |
| `optionalSemantic` | Core AI discovery/prototype work, Vision segmentation, derived-shape fusion, reference-object work |
| `optionalLanguage` | Foundation Models identity enrichment/copilot — prefers review-time execution |

`OptionalWorkExecution` bounds — `oneShot`, `periodic` (budgeted
cadence like the derived-shape preview or stationary reference
detection), `continuous` (full-rate `trackingObjects`, the only
potentially continuous workload in the sibling-issue audit).

## 4. Capture phases

`OptionalWorkPhase` describes what the operator is doing:

| Phase | `CaptureState` source | Rule summary |
|---|---|---|
| `roomScan` | `.scanning` (no active measurement task) | RoomPlan/mesh/depth wins. Continuous optional work prohibited; bounded semantic work only at nominal; language defers to review |
| `targetOrMeasurement` | `.scanning` with `targetScanTracker` active | One task-relevant assist; unrelated semantic/language work defers |
| `reviewAnnotation` | `.reviewing`, `.annotating` | Preferred phase for Foundation Models/Core AI — admission at nominal, defer at elevated, reject at serious |
| `finalizationOrExport` | `.validating`, `.finalized`, `.exported` | Hashing/writing/integrity wins; all optional inference rejected |
| `inactive` | everything else | No capture context to serve; defers |

## 5. Pressure bands

`CapturePressureState` — coarse states derived from existing signals
(the issue's pressure policy), the worst contribution wins:

| Band | Contributed by (any of) |
|---|---|
| `critical` | thermal `.critical`, storage `.critical` — the existing `isLifecycleFailure` conditions |
| `serious` | thermal `.serious`, memory warning active, unresolved ARSession interruption, `.unavailable` tracking — matching the pre-existing rendering/preview mitigation gate |
| `elevated` | thermal `.fair`, storage `.warning`, undetermined storage (not proof of headroom, legacy bolph71656-ai/HTDT-Capture#181), persistence backlog, engaged rendering mitigation, `.limited` tracking, expected-but-absent scene depth |
| `nominal` | nothing above |

Effects: `elevated` defers speculative starts and suspends sustained
in-flight work (bounded one-shots may finish); `serious` rejects
optional starts, cancels in-flight one-shots and suspends sustained
work — retaining only `benchmarkedEssentialAssist` assists (none may
claim that flag before device evidence exists); `critical` cancels
all optional work and the existing failure/recovery policy governs
capture itself.

## 6. Decision semantics

- `allow` — start now.
- `defer` — retry is meaningful when phase or pressure changes
  (assist slot busy, request already in flight, elevated pressure,
  deferred-to-review language work, inactive capture).
- `reject` — prohibited in this context (continuous work during a
  live scan, optional inference during finalization, serious/critical
  pressure).

Denial reasons are machine-stable `snake_case` tokens
(`OptionalWorkDenialReason`) recorded in the decision log and in
advisory-note details — never localized strings.

## 7. Host wiring (App/HTDTCaptureApp.swift)

- `captureHealthSnapshot()` builds `CaptureHealthSnapshot` from
  `ProcessInfo.thermalState`, `resourceMonitor.storagePressureState`,
  the memory-warning mitigation flag, the ARSession interruption
  flag, `store.persistenceBacklogPressureActive`, the rendering
  mitigation flag, latest tracking state, and supported-but-absent
  scene depth.
- The derived-shape preview (optional semantic, periodic) evaluates
  per its existing 16-sample cadence instead of the ad-hoc
  `!resourcePressure` check it used before — the rendering mitigation
  trigger is unchanged.
- The targeted object pass, label scan, and identity/field-evidence
  photo captures register `activeAssist` tickets; `endTargetScan`
  finishes the pass's ticket with its outcome and every request's
  `defer` finishes with `.failed`/`.staleRejected`/`.completed`.
- `applyResourceLifecycleEvent` (the existing single funnel for
  monitor + ARSession lifecycle events) re-derives pressure and
  applies in-flight actions on every event — transitions, not polls,
  shed and reinstate optional work.
- Explicit-request denials set a localized status line **and** record
  a `CaptureAdvisoryNote` of kind `optional_work_admission`, which
  persists in `advisory/operator-advisories.json` and surfaces as a
  Review diagnostic.

## 8. Instrumentation

Only the measurements needed to choose safe defaults (legacy bolph71656-ai/HTDT-Capture#273):

- **Admission decisions**: phase + allow/defer/reject + denial reason,
  bounded to 256 records with identical consecutive verdicts per
  workload compacted (`ScanTrackingTransitionGate` convention);
- **Outcome aggregates** per workload: admitted/deferred/rejected,
  completed/failed/cancelled/stale-rejected, latency count/total/max
  (features supply latency when cheap to measure);
- **AR frame interval distribution**: `ARFrameCadenceTracker`, fed by
  the lifecycle bridge's `didUpdate` frame passthrough inside
  `SharedARSessionController` — bounded 240-interval window plus
  cumulative counts, stretched-frame incidence, max interval;
  `frameCadenceSummary()`/`resetFrameCadenceTracking()` are the
  per-capture benchmark surface. It is a measurement instrument only;
  the admission policy never reads it;
- **Operator provenance**: `optional_work_admission` advisory notes
  for explicit-request denials only — never routine ticks;
- existing signals stay in their authorities: thermal/memory/storage
  timeline in `capture_resource_event`, tracking transitions in the
  bounded legacy bolph71656-ai/HTDT-Capture#148 history, persistence backlog in the store ledger.

Nothing here logs room imagery or geometry as performance telemetry.

## 9. iPhone 17 Pro measured-safe profile (defaults — UNMEASURED)

The legacy bolph71656-ai/HTDT-Capture#267 profile's required output. **No physical iPhone 17 Pro /
iOS 27 benchmark exists yet** — every default below is provisional
policy intent pending the §10 runs and must be recorded as
`measured: false` until then.

| Profile key | Provisional default | Status |
|---|---|---|
| normal video/HDR profile | current default AR config (unchanged by this policy) | unmeasured |
| one-shot high-res policy | one request in flight, owner-bounded (legacy bolph71656-ai/HTDT-Capture#275) | policy in place, latency unmeasured |
| reference detection vs tracking | stationary detection preferred during live scan; full-rate tracking prohibited in `roomScan`/`targetOrMeasurement` | policy in place, unmeasured |
| Vision/Core AI allowed phases | `reviewAnnotation` (one-shots also at nominal `roomScan` for bounded semantic work) | policy in place, unmeasured |
| Foundation Models allowed phases | `reviewAnnotation` only | policy in place, unmeasured |
| pressure/degradation order | shed optionalLanguage → optionalSemantic → non-essential activeAssist; captureCritical never sheds | policy in place, unmeasured |

## 10. Physical benchmark protocol (device-gated)

To be run on iPhone 17 Pro / iOS 27 — **not executed here; no
simulator-only performance claims**:

1. authoritative-capture baseline (~5 min short + ~20–30 min
   sustained workflows);
2. each plausible optional workload separately under the same
   workflows;
3. only the combined profiles that could realistically ship — never
   the Cartesian product of every camera/AI setting.

Measure: thermal timeline, AR frame-cadence distribution,
tracking-limited incidence, sceneDepth availability, RoomPlan/mesh
behavior, persistence latency/backlog, memory warning/crash/
termination, optional-work latency/failure, coarse battery delta,
operator task time, evidence-quality differences. If optional work
materially worsens authoritative evidence, move it to
review/on-demand or disable it — then record the measured-safe
defaults into the §9 profile (`measured: true`).

## 11. Escalation gate: when a real scheduler is justified

Only if GitHub-recorded profiling shows at least one: priority
inversion between coexisting optional tasks; repeated operator
actions needing fair/bounded queueing rather than reject/defer;
cancellation/preemption that must be coordinated across feature
owners; or throughput that phase/admission rules cannot control.
Until such evidence exists, the small admission policy stands —
the issues' own audit bounds nearly all proposed work already.
