# Physical capture corrections — 2026-09-20

Issue: legacy bolph71656-ai/HTDT-Capture#80  
Implementation PR: legacy bolph71656-ai/HTDT-Capture#81  
Starting authority: `fe4bf31d0f53eeef87147a1b687d4a303d36a3ed`

## Reported physical-device failures

The 2026-09-20 iPhone acceptance pass exposed three coupled problems:

1. scan guidance reached 100% and displayed the completion message, but ending the scan could still enter `failed` with a persistence error while the UI remained on “Saving available mesh evidence”;
2. a connected multi-level object, such as a smaller rectangular body above a larger rectangular body, was reduced to one coarse footprint;
3. round/curved furniture was still visually dominated by the coarse RoomPlan/ARMesh reconstruction and the derived-shape path could select a polygonal approximation instead of the stronger observed scene-depth contour.

The 100% guidance value is advisory coverage state. It is not, and must not become, permission to ignore canonical evidence integrity. The correction instead removes avoidable persistence failures after valid canonical frame/depth evidence has already been retained.

## Root causes and corrections

### End-scan persistence

`RoomCaptureViewDelegate` completion may be delivered again around the stop/review transition. The working-set store previously treated an exact replay of the canonical RoomPlan raw or processed path as a duplicate declaration error.

The store now treats an **exact descriptor replay as idempotent**. A conflicting second payload remains rejected.

End-scan ARMesh persistence is also now best-effort after frame/depth evidence has already been persisted. A mesh write failure records a warning resource event instead of immediately destroying the capture. The production host enables an explicit quality rule allowing real retained depth evidence to substitute for a missing mesh anchor. The core rule remains opt-in/fail-closed by default.

This fallback does not synthesize geometry and does not relax RoomPlan, frame/depth, or bundle-integrity requirements.

### Curved furniture

The live derived furniture path previously selected semantic ARMesh whenever eight or more mesh points were available, even when scene depth was also available. This favored coarse rectangular semantic reconstruction for round tables and curved seating.

The derived object path now:

- uses a more focused center scene-depth crop for furniture fitting;
- prefers real scene-depth object observations when sufficient evidence exists;
- keeps ARMesh as a bounded fallback;
- preserves the existing ambiguity/fail-closed rules in the shape fitter.

The white RoomPlan model remains an Apple-provided coarse live reconstruction and is not upgraded into curved ground truth. The derived observed-shape authority is the scene-depth-backed path.

### Connected multi-level geometry

The 3D decomposer intentionally keeps genuinely connected/stepped geometry together so it does not over-split one object. Changing that invariant would regress continuous stepped furniture.

Instead, a new bounded horizontal-profile extractor finds up to three well-supported, vertically separated silhouettes whose extents materially differ. Sparse legs and weak bands are excluded by relative horizontal-support thresholds. These profiles are independently fitted in the live derived preview, allowing a large lower body and smaller upper body to remain visible as separate observed profiles without inventing a gap between them.

## Automated validation

Focused regression coverage was added for:

- exact duplicate RoomPlan completion replay;
- strict quality behavior versus explicit scene-depth mesh fallback;
- materially different stacked horizontal profiles.

Repository-native `swift test`, iOS platform/AppShell compilation, and the unsigned IPA build are the software-verification authority for this slice (all run locally; no CI exists).

## Physical-device acceptance still required

CI cannot establish camera/depth quality in the reported room. Before closing legacy bolph71656-ai/HTDT-Capture#80, verify on the same or equivalently difficult physical scene:

- guidance can reach completion and **End** reaches review instead of a persistence failure;
- a round table reports a scene-depth-derived circle/ellipse when the observed contour supports it, rather than a forced rectangle;
- curved chair/sofa evidence is not replaced by a semantic rectangular proxy in the derived shape result; ambiguous evidence must remain ambiguous/polygonal rather than fabricated;
- connected large-base/small-top furniture exposes more than one materially different horizontal profile when both levels are observed;
- long scans do not reintroduce the earlier memory/crash regression.

If any physical case fails, retain the captured evidence and update legacy bolph71656-ai/HTDT-Capture#80 with the exact geometry badge, evidence counts, and failure state before further threshold changes.


## Second physical-device pass — 19:48–19:49 JST

The first correction (legacy bolph71656-ai/HTDT-Capture#81) improved the software authority but did **not** close the physical regression. The supplied second-pass screenshots establish the following current-device facts:

- tracking remained normal;
- direction coverage reached 100% and the guidance UI reported completion;
- spatial observation was explicitly using scene depth;
- the expanded HUD reported scene reconstruction enabled but no ARMesh anchors observed;
- at least one evidence frame was already retained;
- pressing **End** still transitioned to `failed` with a generic persistence failure while the visible stage text was stale at “Saving available mesh evidence”;
- the derived shape badge still reported `Polygon` in a scene containing round/curved furniture.

PR bolph71656-ai/HTDT-Capture#82 therefore targets a narrower remaining failure surface.

### Remaining end-scan race

The legacy bolph71656-ai/HTDT-Capture#81 replay guard only handled a duplicate callback **after** the first RoomPlan descriptor had committed to actor state. The store actor can re-enter while awaiting its file-writer actor, so two identical completion callbacks can both observe a nil descriptor before either commit finishes.

The correction adds a byte-identical atomic writer path. If the canonical target appears because another identical writer won the race, the second writer accepts it only when the existing bytes exactly match. Conflicting bytes remain a hard error. Payload declaration registration is likewise idempotent only for an exactly equal declaration.

A successful mesh snapshot with zero anchors is now treated as mesh-unavailable and no empty mesh package is written. The existing real-depth fallback is used instead.

Residual raw/processed RoomPlan write failures now replace the stale stage string with the actual failing stage before transitioning to `failed`.

### Depth target isolation

The prior derived-shape path projected most of the center camera crop into one object observation. On the physical scene, the round table, chair, floor, cabinet, and nearby objects can therefore contribute to one connected footprint and bias the fitter toward a polygon.

PR bolph71656-ai/HTDT-Capture#82 introduces a bounded image-grid connected-surface selector for the **derived object-shape path only**:

- seed from the closest valid depth surface in a central window;
- flood only through neighboring depth samples whose local depth discontinuity stays within an absolute/relative bound;
- preserve smooth curved depth continuity;
- reject disconnected background surfaces separated by a material depth jump;
- fall back to the unsegmented valid samples when no sufficiently supported component exists.

Whole-room spatial coverage is unchanged. This selector does not synthesize unseen geometry and is advisory only.

### Added regression coverage

PR bolph71656-ai/HTDT-Capture#82 adds focused tests for:

- byte-identical atomic replay versus conflicting overwrite;
- concurrent identical RoomPlan raw/processed completion replay;
- foreground/background depth separation;
- smooth curved depth continuity.

Physical acceptance remains required after CI passes.
