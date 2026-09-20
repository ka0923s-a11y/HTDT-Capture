# Guided Scanning UX Plan

Status: G100A/G100B implemented by PR #47; G100C implemented by PR #49; G100D implemented by PR #53; G100E observation confidence implemented by PR #59; G100F current-relative direction guidance implemented by PR #60; physical-device acceptance remains open.  
Scope: scanner-first iOS UX; no Capture Bundle schema promotion in these slices.

## 1. Problem statement

The capture engine can collect RoomPlan, AR mesh, camera, and depth evidence, but
the current `scanning` state is presented primarily as a status list. On a
physical LiDAR iPhone this hides the most important operator feedback:

- the live camera/AR view;
- which room structures RoomPlan currently recognizes;
- how the operator should move;
- whether tracking is healthy;
- which look directions have received little or no observation;
- whether it is reasonable to end the scan.

For HTDT this is not only a presentation problem. Capture quality depends on
deliberate acquisition from varied positions and angles, while the canonical
bundle must continue to distinguish observed evidence from heuristics.

## 2. Reference patterns

The product direction is based on documented capture patterns rather than
copying any third-party visual design.

### Apple RoomPlan

Use the framework-provided `RoomCaptureView` with the app-owned `ARSession`.
Apple documents that this view provides:

- a live camera feed;
- real-time graphical overlays on recognized structures;
- scan instructions/coaching;
- an optional miniature model showing scan progress.

Primary references:

- https://developer.apple.com/documentation/roomplan/roomcaptureview
- https://developer.apple.com/documentation/roomplan
- https://developer.apple.com/documentation/roomplan/roomcapturesession/instruction

### Scaniverse

Public Scaniverse guidance emphasizes slow natural movement, varied high/low
and near/far viewpoints, and revisiting regions that still look under-captured.

Reference:

- https://scaniverse.com/support

### Polycam

Polycam's public review/render workflow exposes multiple representations of a
capture so quality and geometry can be inspected rather than hidden.

Reference:

- https://learn.poly.cam/hc/en-us/articles/28785257328276-How-to-Use-Render-Mode

These are interaction principles only. HTDT-Capture keeps its own authority,
quality, and provenance model.

## 3. UX authority boundary

The scan UI must never imply that a visual progress indicator is canonical
measurement truth.

Three separate concepts remain explicit:

1. **RoomPlan semantic approximation**
   - the Apple-owned live camera overlay, structural lines, miniature model,
     and coaching are a semantic approximation for operator guidance;
   - the early live outline can simplify, move, or change as RoomPlan observes
     more of the room;
   - HTDT does not relabel or mutate RoomCaptureView's private/undocumented
     subviews and does not present those live lines as canonical geometry.

2. **HTDT observation confidence**
   - an app-owned, ephemeral guidance state describing how repeatedly and
     diversely the current spatial direction/region has been observed;
   - states are `provisional`, `accumulating`, and `well_observed`;
   - evidence inputs are repeated normal-tracking samples, viewing-angle
     diversity, scene-depth availability, active ARMesh support, and bounded
     camera-movement consistency;
   - limited/unavailable tracking does not advance confidence;
   - a bounded mismatch heuristic may request a shape recheck when trajectory
     evidence is sufficient but supporting depth/mesh observation remains weak,
     or when supporting evidence drops after a well-observed state;
   - this confidence is capture guidance only. It is not a RoomPlan correctness
     probability, measurement truth, a finalization gate, or a persisted schema
     field.

3. **Canonical evidence**
   - exact raw RoomPlan result;
   - exact selected ARFrame image/depth records;
   - exact ARMesh snapshots;
   - explicit user-attested annotations/measurements;
   - persisted using the existing Capture Bundle contracts.

The authority order is therefore: RoomPlan live overlay = semantic
approximation; HTDT observation confidence = capture guidance; raw
RoomPlan/ARFrame/depth/ARMesh artifacts = evidence authority.

G100F current-relative direction guidance remains inside the same advisory
boundary. Its selected target cell, signed yaw/pitch errors, angular distance,
arrow, relative-compass markers, and hysteresis state are camera-trajectory
guidance only. They are not Capture Bundle measurements, do not prove geometric
completeness, and do not participate in finalization gates.

## 4. Scanner-first screen

When `CaptureState == .scanning`, the normal status list is replaced by a
full-screen scanner composition.

### 4.1 Primary layer

- live `RoomCaptureView`;
- the exact same app-owned `ARSession` used by the evidence pipeline;
- RoomPlan structural overlays enabled;
- RoomPlan miniature model enabled;
- no second competing RoomPlan or AR session.

### 4.2 Top HUD

Display a compact material panel containing:

- current HTDT guidance text;
- tracking state;
- advisory coverage percentage;
- active mesh-anchor count.

Guidance priority:

1. tracking unavailable/limited;
2. insufficient low-angle coverage;
3. insufficient high-angle coverage;
4. horizontal coverage gap;
5. broad coverage achieved; ask the operator to inspect RoomPlan overlays for
   remaining unrecognized structures.

The framework-provided RoomPlan coaching remains visible as well.

### 4.3 Coverage indicator

Use a 12-sector horizontal compass. Each sector summarizes three look-angle
bands:

- low: camera forward pitch below -20 degrees;
- level: -20 through +20 degrees;
- high: above +20 degrees.

A cell becomes observed only from a usable tracking sample. A sector's visual
fill reflects how many of its three bands have been observed.

The initial normal-tracking camera heading becomes the relative forward
reference for the compass. This is deliberately a trajectory-coverage
heuristic, not a map of room surfaces.

### 4.4 Bottom controls

Keep only primary scan actions on the camera screen:

- **Save evidence frame**
- **End scan and review**

Secondary status/debug information remains available after the scan or in
diagnostic views rather than displacing the camera.

## 4.5 Live-view lifecycle requirement

Physical-device acceptance found a black preview even while the shared
`ARSession` reported normal tracking and advisory coverage advanced. The
renderer lifecycle is therefore part of the scanner contract, not merely a
presentation detail.

The host must:

1. transition into the scanning presentation so the exact
   `RoomCaptureView` is mounted in the window hierarchy;
2. verify that the mounted view has a non-empty laid-out bounds;
3. only then call that view's `captureSession.run(...)`;
4. fail closed if the live capture view does not attach within the bounded
   presentation window.

Starting RoomPlan while the framework-provided view is still detached is not
an accepted host sequence. A second camera/AR session must not be introduced as
a workaround because that would split the capture and display authorities.

## 4.6 Approximation and observation-confidence presentation

The scanner HUD carries a compact `RoomPlan approximation` label and a separate
HTDT observation state. The app does not attempt to recolor or replace Apple's
RoomPlan structural lines with fake "provisional" or "final" geometry.

When the bounded observation heuristic sees a repeatedly viewed region with
weak supporting depth/mesh evidence, the scanner may show:

- **Recheck shape**
- **Show this area again from another angle.**

This is deliberately advisory wording. It does not assert that RoomPlan is
wrong. A recheck advisory is not persisted as measurement truth.

## 5. Coverage model v1

### 5.1 Sampling

Sample at approximately 4 Hz while scanning. Each sample contains:

- monotonic ARFrame timestamp;
- camera yaw;
- camera pitch;
- AR tracking state and reason;
- active ARMesh anchor count;
- sceneDepth presence.

Sampling is bounded and keeps no pixel/depth payload copies.

### 5.2 Binning

- 12 equal azimuth sectors;
- 3 pitch bands;
- 36 cells total;
- repeated samples in a cell are counted;
- v1 considers a cell observed after two normal-tracking samples.

Coverage fraction:

`observed_cells / 36`

This fraction is intentionally advisory. A high number does not prove complete
room geometry and a low number does not invalidate already captured evidence.

### 5.3 Gap selection

The next suggested gap is chosen deterministically:

1. prefer the sector with the fewest observed pitch bands;
2. break ties by smallest angular distance from the current relative heading;
3. prefer missing level, then low, then high within that sector.

The selected target is a **start-relative coverage cell**: one azimuth sector
relative to the first normal-tracking camera heading plus one pitch band. It is
not a room-surface identity.

### 5.4 Current-relative guidance geometry

The UI must not ask the operator to mentally convert a start-relative label such
as "rear right" into a physical turn from the phone's current pose. G100F
therefore derives a presentation-only guidance authority from the selected
start-relative target:

- target yaw = center heading of the selected 12-way azimuth sector;
- target pitch = representative center for low / level / high;
- signed yaw error = wrapped target yaw minus current start-relative yaw;
- pitch error = target pitch minus current camera pitch;
- angular distance = spherical angular separation between current and target
  look directions.

Positive signed yaw error means turn right; negative means turn left. Positive
pitch error means raise the camera view; negative means lower it. The UI maps
those continuous errors into eight directional arrows. When both errors are
within configured alignment tolerances, the instruction changes to "Slowly
scan this direction" instead of continuing to show a turn arrow.

This distinction is intentional:

- **start-relative** answers "which coverage cell is missing?";
- **current-relative** answers "which way should I turn right now?".

### 5.5 Guidance stability / hysteresis

Target selection is stateful and deterministic. Guidance timing and angular
thresholds are centralized in `ScanGuidanceConfiguration`.

1. a newly selected target is held for at least the configured minimum hold
   interval while it remains unobserved;
2. after the hold interval, an unobserved target is retained unless another
   sector has strictly fewer observed pitch bands;
3. when the target cell becomes observed, the next deterministic gap is
   selected immediately.

The hysteresis affects operator guidance only. It does not change cell
observation counts or canonical evidence.

## 6. Interruption and failure presentation

This slice retains the typed failure state but the live scanner must make
tracking degradation visible before a terminal failure when possible.

The plan for subsequent recovery work is:

- distinguish app/background interruption from AR tracking loss;
- expose a recover/relocalize path only when the same coordinate-space
  authority can be preserved;
- otherwise end the scan segment or fail closed and create a new coordinate
  authority rather than pretending continuity.

## 7. End-scan completeness review

When **End scan** is selected with substantial advisory gaps, the scanner
presents a non-blocking coverage review sheet.

Implemented behavior:

- overall plus low / level / high coverage percentages;
- the most under-observed relative compass directions;
- **Continue scanning** as the safe recovery path;
- explicit **End anyway** because the heuristic is not canonical authority;
- no bundle-schema or finalization-gate change.

The sheet is shown when overall coverage is below 75%, or low/high coverage is
below 50%. These are UX prompting thresholds only; they are not accuracy or
ingestion requirements.

## 8. Localization

All operator-facing scanner copy must support Japanese and English.

Japanese terminology:

- Scan coverage: `見回しカバレッジ`
- Tracking normal: `トラッキング正常`
- Tracking limited: `トラッキング制限あり`
- Under-observed direction: `未取得方向`
- Evidence frame: `証拠フレーム`

Raw enum/debug tokens may remain English only in developer diagnostics.

## 9. Implementation slices

### G100A — live scanner foundation — implemented

- make `RoomCaptureView` the exact RoomPlan capture session view;
- SwiftUI bridge for the shared capture view;
- scanning-state full-screen camera UI;
- preserve existing raw RoomPlan completion pipeline.

### G100B — advisory coverage telemetry — implemented

- deterministic core coverage tracker;
- platform ARFrame observation adapter;
- bounded host sampling task;
- coverage compass and tracking HUD;
- Japanese/English copy.

### G100C — end-scan gap review — implemented

- gap summary sheet;
- continue/end decision;
- optional persisted diagnostic only after authority/schema review.

### G100E — RoomPlan approximation / HTDT observation confidence — software implemented

- label the Apple-owned RoomPlan overlay as a live semantic approximation;
- add app-owned `provisional` / `accumulating` / `well_observed`
  observation confidence for the current spatial direction;
- require repeated, multi-angle, depth, mesh, and movement evidence before
  `well_observed`;
- add a bounded recheck advisory without declaring RoomPlan incorrect;
- keep confidence ephemeral and outside Capture Bundle schema authority;
- leave physical-device visual acceptance open.

### G100F — current-relative direction guidance — software implemented

- retain the 12 x 3 start-relative advisory coverage authority;
- compute continuous signed yaw error, pitch error, target sector / band, and
  angular distance from the live camera pose;
- map errors to left/right/up/down and diagonal arrows, with an aligned
  slow-scan state;
- emphasize the recommended coverage cell with a focus border/marker;
- show a compact relative compass distinguishing start, current, and target;
- apply deterministic target hysteresis from the core model;
- keep all guidance advisory and ephemeral;
- leave physical-device visual acceptance open.

### G100D — interruption/relocalization UX — implemented fail-closed baseline

- terminal interruption/failure screens now explain the reason and recovery path;
- leaving the foreground during active capture is shown explicitly instead of
  leaving a stale scanning status;
- terminal failures stop/pause the shared RoomPlan / AR session;
- the UI does not offer same-session resume because coordinate continuity has
  not been independently demonstrated;
- reset creates a fresh AR session / coordinate-space authority;
- ARWorldMap or equivalent proven relocalization remains future research.

## 10. Acceptance criteria for G100A/B/C/D/E/F

Automated:

- deterministic coverage tracker tests pass;
- deterministic observation-confidence transitions and recheck heuristic tests pass;
- existing core tests remain green;
- iOS platform/AppShell compile succeeds;
- unsigned IPA archive succeeds.

Physical-device gate:

- scanning visibly opens the rear camera;
- RoomPlan overlays/coaching are visible and are not materially obscured by
  the HTDT direction overlay;
- early RoomPlan lines are visibly framed as an approximation rather than
  measurement truth;
- the current HTDT observation state is understandable while scanning;
- a recheck advisory is visible when supporting observation remains weak;
- the Apple-owned RoomPlan overlay remains intact and unmodified;
- miniature model updates;
- coverage HUD updates while the user changes direction and pitch;
- a user can follow the arrow without first interpreting labels such as
  "rear right";
- rotating the phone changes the arrow naturally relative to the current pose;
- the recommended 12 x 3 target cell is immediately distinguishable from other
  unobserved cells;
- aiming at the target and observing it advances guidance to the next gap;
- the start/current/target relative compass remains understandable in portrait
  use;
- no second AR/RoomPlan session is created;
- ending the scan still persists the exact raw RoomPlan result and scan-end
  mesh/frame evidence;
- Japanese UI is legible on the target iPhone.

CI success is not evidence that these physical-device requirements passed.


## 11. G110 spatial / surface-aware advisory coverage

G110 adds a second advisory coverage authority alongside the existing
12-azimuth × 3-pitch trajectory coverage and G100E observation confidence.
It does not replace either layer and is not promoted into the Capture Bundle
or finalization gates.

### 11.1 Mesh availability authority

The live scanner diagnoses the active ARSession configuration rather than
showing only a raw mesh count. The states are:

- **mesh unavailable**: supported scene reconstruction is not enabled in the
  active configuration;
- **mesh enabled, no anchors yet**: reconstruction is enabled but the current
  frame contains no ARMeshAnchor;
- **mesh anchors observed**: at least one current mesh anchor is present.

When the device supports scene reconstruction but the active configuration has
it disabled, the UI explicitly reports a configuration mismatch and notes that
RoomPlan may have changed the shared session configuration. Spatial coverage
does not silently fall back to direction coverage.

### 11.2 Bounded spatial representation

The live path samples at most 96 representative ARMesh vertices per spatial
update and only accumulates candidates inside a bounded approximation of the
current camera frustum (0.15–6 m). This prevents retained ARMesh anchors outside
the current view from gaining observation count merely because they remain in
the AR session. It does not serialize or clone canonical mesh payloads at UI
rate.

The deterministic core aggregator uses:

- start-position / start-heading-relative XZ coordinates;
- fixed 0.5 m cells;
- maximum 256 retained regions with deterministic oldest-region eviction;
- a maximum 13 × 13 display window around the current camera;
- approximately 2 Hz spatial updates, while direction/observation sampling
  remains approximately 4 Hz;
- actor-isolated aggregation so cell classification work does not execute on
  the main actor.

Each retained region tracks observation count, last observation time,
normal/limited tracking counts, 8-bin view-angle diversity, camera-distance
bucket, depth-presence count, and mesh-support count.

### 11.3 Classification semantics

- **unknown**: no spatial observation authority exists for that display cell;
- **weak**: mesh-backed observation exists but normal-tracking count and/or
  view-angle diversity is insufficient;
- **observed**: at least three normal-tracking observations from at least two
  view-angle buckets support the region.

Limited-tracking samples can keep a region weak but cannot promote it to
observed. Tracking-unavailable samples are rejected from spatial accumulation.

Unknown is deliberately neutral. It must not be rendered or described as a
missing wall, missing furniture, or failed geometry reconstruction.

### 11.4 Scanner and end-review UX

The scanner includes a collapsible start-relative top-down map showing:

- current camera position and heading;
- observed regions;
- weak regions;
- unknown/no-authority cells.

The mesh diagnostic distinguishes the three availability states above. The
existing end-scan review now has separate **Direction coverage** and **Spatial
coverage** sections. Spatial labels are relative regions such as
**Rear right region**; no furniture semantic is guessed.

### 11.5 Authority and performance boundaries

G110 remains ephemeral advisory UX:

- it never synthesizes unseen geometry;
- unknown does not mean missing wall/surface;
- it never replaces canonical ARMesh snapshots;
- it is not a finalization gate;
- it makes no accuracy claim before physical benchmark evidence;
- it keeps bounded memory and bounded per-update mesh sampling.

Automated acceptance covers deterministic aggregation tests, core tests, iOS
compile, and unsigned IPA generation. Physical LiDAR validation remains a
separate gate for mesh-availability truthfulness, heatmap motion, weak/unknown
distinction, camera-follow behavior, and RoomPlan capture performance.


## 11. Derived observation shape preview

The complex-shape preview is specified in
[`DERIVED_OBSERVATION_SHAPE_PREVIEW.md`](DERIVED_OBSERVATION_SHAPE_PREVIEW.md).

It extends the scanner without changing the authority hierarchy:

- RoomPlan remains the semantic structural approximation;
- G110 remains the live spatial observation / mesh-availability authority;
- classification-aware bounded ARMesh observations may be fit to circle,
  ellipse, oriented-rectangle, polygon, or non-orthogonal wall-chain proxies;
- insufficient or ambiguous evidence remains unresolved rather than being
  forced into a rectangle;
- the derived proxy is preview-only and never becomes canonical geometry or a
  finalization gate in this slice.

The live implementation is deliberately bounded. Shape observations are sampled
only when G110 reports active mesh anchors, face inspection and point counts are
capped, and numerical fitting runs off the main actor. Physical LiDAR acceptance
is still required for circular tables, oblique walls, polygonal boundaries,
performance, and operator comprehension.
