# Guided Scanning UX Plan

Status: G100A/G100B implemented by PR #47; G100C implemented by Issue #48 branch; physical-device acceptance and G100D remain open.  
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

1. **RoomPlan live feedback**
   - framework-generated camera/AR overlay and coaching;
   - useful for operator guidance;
   - not independently promoted as HTDT measurement authority.

2. **HTDT advisory coverage telemetry**
   - derived from live ARFrame camera trajectory, tracking, depth presence, and
     current ARMesh anchor count;
   - guides the operator toward under-observed directions;
   - ephemeral in this slice;
   - does not alter bundle identity, finalization rules, or semantic geometry.

3. **Canonical evidence**
   - exact RoomPlan raw result;
   - exact selected ARFrame image/depth records;
   - exact ARMesh snapshots;
   - explicit user-attested annotations/measurements;
   - persisted using the existing Capture Bundle contracts.

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

This avoids a random or oscillating instruction stream.

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

### G100D — interruption/relocalization UX

- detailed interruption causes;
- recover only when coordinate continuity can be demonstrated;
- fail closed otherwise.

## 10. Acceptance criteria for G100A/B/C

Automated:

- deterministic coverage tracker tests pass;
- existing core tests remain green;
- iOS platform/AppShell compile succeeds;
- unsigned IPA archive succeeds.

Physical-device gate:

- scanning visibly opens the rear camera;
- RoomPlan overlays/coaching are visible;
- miniature model updates;
- coverage HUD updates while the user changes direction and pitch;
- no second AR/RoomPlan session is created;
- ending the scan still persists the exact raw RoomPlan result and scan-end
  mesh/frame evidence;
- Japanese UI is legible on the target iPhone.

CI success is not evidence that these physical-device requirements passed.
