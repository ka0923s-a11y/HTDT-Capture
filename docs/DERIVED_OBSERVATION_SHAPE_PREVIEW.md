# Derived observation shape preview

Status: implementation slice for complex-shape-aware capture preview.

This slice adds an evidence-backed, non-canonical geometry layer alongside
RoomPlan. It does not replace RoomPlan, change the Capture Bundle canonical
schema, or promote derived geometry into backend authority.

## Authority relationship

The capture pipeline intentionally keeps four concepts separate:

1. **RoomPlan semantic approximation**
   - Framework-provided semantic room/object representation.
   - Useful for labels, room structure, and framework-native guidance.
   - May visually simplify circular, elliptical, oblique, or polygonal forms.

2. **ARMesh / depth observed geometry**
   - Raw or bounded observations tied to the capture coordinate space.
   - ARMesh is consumed directly in this slice.
   - The derived observation interface is source-neutral and accepts mesh,
     scene-depth, or future spatial-observation evidence kinds so G110/depth
     sources can connect without changing the fitting authority.

3. **HTDT derived proxy**
   - A bounded preview-only shape proxy derived from observed evidence.
   - Candidate families are oriented rectangle, circle, ellipse, and polygon.
   - Every proxy keeps source evidence refs, coordinate-space authority,
     algorithm/version, residual/support/fit score, and observation time range.
   - Weak or conflicting evidence remains insufficient or ambiguous; there is
     no forced rectangle fallback.

4. **Canonical authority**
   - Unchanged by this slice.
   - RoomPlan raw/processed artifacts, mesh evidence, frame/depth evidence, and
     existing canonical capture records remain the persisted authorities.
   - Derived preview geometry is advisory and is not silently promoted.

In compact form:

    RoomPlan semantic structure ----------------------+
                                                       |
                                                       v
                                              operator comparison
                                                       ^
                                                       |
    ARMesh / depth observations -> bounded reduction -> derived shape proxy
                                                       |
                                                       v
                                              preview only in this slice

    canonical Capture Bundle authority: unchanged

## Observation extraction

MeshDerivedShapeObservationBuilder consumes MeshAnchorSnapshot evidence.

The extraction path is deterministic and bounded:

- transform mesh vertices into the capture coordinate space;
- optionally restrict to a caller-provided 3D region;
- optionally restrict faces by ARMesh classification;
- keep triangle boundary edges preferentially so surface interiors do not
  dominate footprint fitting;
- project the selected boundary to the X/Z working plane;
- apply 2D voxel reduction;
- deterministically cap the preview point count.

The default cap is 512 points. The UI keeps at most a 96-point observation
sample per proxy. An unbounded point cloud is never retained by the preview
model.

The source-neutral DerivedShapeObservation / DerivedShapeObservationSource
interface is the seam to the G110 spatial-observation authority. G110 is already
present on main: its mesh-availability diagnostic is the live gate for derived
preview work, and its bounded spatial sampling cadence remains the scanner
authority for whether ARMesh evidence is actually available.

For shape fitting, the platform adapter adds a classification-aware bounded
view over the same active ARMesh anchors. It reads only a capped number of live
faces, retains boundary-supported points, applies 2D voxel reduction, and passes
at most the configured point budget into the source-neutral observation type.
It does not serialize the full canonical mesh at UI cadence. Heavy connected-
component and fitting work runs off the main actor. This keeps G110 and derived
shape preview complementary rather than duplicating a second unbounded live
mesh pipeline.

## Shape fitting and selection

For each bounded observation, the fitter evaluates:

- minimum-area oriented rectangle over the convex hull;
- circle fit from radial residual;
- PCA-oriented ellipse fit;
- bounded concave-capable polygon footprint.

Each candidate reports normalized residual, support score, and fit score.

Selection adds a deterministic model-complexity penalty so a polygon does not
win merely because it has more degrees of freedom. Strong parametric evidence
therefore wins when appropriate, while pentagonal/L-like evidence can still
select a polygon.

A candidate is not selected when there are too few usable points, spatial
extent is too small, the best residual/support is outside bounded acceptance
thresholds, or the top candidates are materially ambiguous. This is deliberate:
the preview reports an unresolved shape instead of pretending that a rectangle
is authoritative.

## Wall / boundary behavior

Wall-classified ARMesh observations are projected without axis alignment.
The resulting polygon/wall chain preserves arbitrary headings and can contain
more than four segments. Polygon vertices carry nearby evidence refs so
individual boundary vertices remain traceable to observation support.

No step in this slice constructs a room-wide axis-aligned rectangle.

The disagreement detector can flag non-rectangular observed object shape versus
a rectangle-compatible semantic approximation, non-orthogonal wall headings,
and multi-segment boundaries. The UI wording states only that the semantic
estimate and observed shape differ. It does not declare either representation
correct.

## Preview UI

The scanning view adds a distinct derived-geometry panel with three modes:

- **RoomPlan structure** — framework semantic view only;
- **Observed shape** — RoomPlan is visually deemphasized and the HTDT derived
  top-down proxy is shown;
- **Overlay** — both are shown together.

Derived object geometry uses an orange dashed outline. Derived wall chains use
a cyan line with supported vertices. They intentionally do not look like the
RoomPlan white structure lines.

When evidence is insufficient or ambiguous, the panel displays an unresolved
state and observation samples rather than drawing a fabricated rectangle.

## Scope boundaries

Not included:

- CAD reconstruction;
- curved-wall NURBS;
- ML object recognition/classification;
- canonical semantic promotion;
- inference of unseen geometry;
- Capture Bundle schema changes.

Depth integration can use the same source-neutral observation seam later.
G110 integration is active in this slice: G110 mesh availability gates the
preview, while classification-aware bounded points provide the object/wall
shape evidence needed for fitting.

## Automated acceptance

The core test suite includes synthetic fixtures for perfect circle, ellipse,
rotated rectangle, pentagon, L-like concave polygon, noisy circle, insufficient
points, ambiguous circle-vs-square evidence, non-orthogonal wall chain,
deterministic output, and ARMesh boundary extraction/point bounding.

Repository CI additionally compiles the iOS platform/app targets and builds the
unsigned IPA.

## Physical-device acceptance gate

Physical LiDAR acceptance remains explicit and must be performed on a supported
device:

- a circular table with sufficient evidence can resolve to circle/ellipse;
- oblique walls are not snapped to 90 degrees;
- polygonal footprints are not forced into rectangles;
- weak evidence remains unresolved;
- RoomPlan semantic structure and HTDT observed geometry are visually
  distinguishable.

The physical-device gate is intentionally not claimed by automated CI.
