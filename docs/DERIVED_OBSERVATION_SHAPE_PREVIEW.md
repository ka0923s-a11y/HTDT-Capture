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
Circle and ellipse candidates additionally report angular support. A closed
object proxy is not resolved unless the observation surrounds the fitted
footprint sufficiently: partial/single-direction arcs remain
insufficientEvidence even when their local radial residual is low.

Selection uses a deterministic model-complexity penalty, but the rectangle is
not a privileged fallback. The relative penalty was rebalanced so a supported
five-plus-vertex polygon is not suppressed merely for having more vertices.
Strong parametric evidence still wins when appropriate. Weak or competing
evidence resolves only as resolved, insufficientEvidence, or ambiguousEvidence;
there is no "unknown -> rectangle" path.

Concavity is treated as a separate evidence question. A concave polygon is
retained only when reflex vertices and both adjacent boundary segments have
local observation support. Otherwise the preview uses the bounded convex
observed boundary and records concavityResolution=unresolved. It never invents
hidden concavity from sparse evidence.

A candidate is not selected when there are too few usable points, spatial
extent is too small, angular support is insufficient, the best
residual/support is outside bounded acceptance thresholds, or the top
candidates are materially ambiguous. This is deliberate: the preview reports
an unresolved shape instead of pretending that a rectangle is authoritative.

## Wall / boundary behavior

Wall-classified ARMesh observations are projected without axis alignment.
The resulting polygon/wall chain preserves arbitrary headings and can contain
more than four segments. Polygon vertices carry nearby evidence refs so
individual boundary vertices remain traceable to observation support.

No step in this slice constructs a room-wide axis-aligned rectangle.

The disagreement-risk advisory can flag non-rectangular observed object
evidence, non-orthogonal wall headings, and multi-segment boundaries. Because
the live public RoomPlan view does not expose exact semantic geometry here, the
UI does not claim that an exact RoomPlan discrepancy was measured. It says the
observed geometry may differ and asks the operator to compare the two visible
representations. No unavailable RoomPlan discrepancy metric is inferred.

## Preview UI

The scanning view adds a distinct derived-geometry panel with three modes:

- **RoomPlan structure** — explains that the live camera surface is the
  framework RoomPlan semantic approximation;
- **Observed shape** — shows the separate HTDT-derived top-down proxy;
- **Compare** — keeps both meanings visible for operator comparison.

The public RoomCaptureView does not expose a supported way to independently
dim only its white semantic lines while preserving the camera image. HTDT
therefore does not reduce opacity of the whole camera view just to suppress
RoomPlan graphics. Instead, the collapsed observed-shape badge remains visible
and the tapped detail preview uses a visually distinct orange dashed object
outline and cyan wall chain. This slice does not claim a camera-registered 3D
overlay because the public RoomPlan live view does not expose the semantic
geometry needed to align a second renderer safely.

When derived evidence exists, the collapsed scanner control exposes a compact
operator-visible badge such as Observed shape: Circle / Ellipse / Polygon or an
unresolved state. Tapping expands the detailed preview. This keeps the live
camera first while making evidence-backed non-rectangular observations visible
without requiring the operator to discover an expanded panel.

When evidence is insufficient or ambiguous, the panel displays an unresolved
state and observation samples rather than drawing a fabricated rectangle.
Polygon detail also states when concavity is unresolved.

RoomPlan semantic approximation, HTDT observed derived shape, and canonical
geometry are three distinct authorities:

    RoomPlan semantic approximation
        != HTDT observed derived shape
        != canonical geometry

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

The core test suite includes synthetic fixtures for perfect circle, noisy
circle, partial circle arc, ellipse, near-square rounded shape, rotated
rectangle, pentagon, supported L-like concavity, sparse/unresolved concavity,
insufficient points, ambiguous circle-vs-square evidence, non-orthogonal wall
chain, deterministic output, and ARMesh boundary extraction/point bounding.

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
