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

Local builds additionally compile the iOS platform/app targets and produce the
unsigned IPA (no CI exists).

## Physical-device acceptance gate

Physical LiDAR acceptance remains explicit and must be performed on a supported
device:

- a circular table with sufficient evidence can resolve to circle/ellipse;
- oblique walls are not snapped to 90 degrees;
- polygonal footprints are not forced into rectangles;
- weak evidence remains unresolved;
- RoomPlan semantic structure and HTDT observed geometry are visually
  distinguishable.

The physical-device gate is intentionally not claimed by automated checks.


## Vertical occupancy and support-element derivation

The derived preview now carries bounded world-Y evidence in addition to the
existing X/Z footprint samples. This is still preview-only authority: the added
vertical samples are not promoted into the Capture Bundle schema or canonical
room geometry.

`DerivedSupportAnalyzer` converts the bounded object observation into coarse
height slices and horizontal occupancy columns. The analysis is capped at 1,024
points and uses deterministic height/voxel bins. It identifies the upper
furniture body from broad occupancy, then looks only for observed narrow
vertical components below that body.

The typed support result can represent:

- multiple observed legs;
- one narrow vertical column;
- a wider observed pedestal;
- a body whose observed occupancy reaches the floor;
- a body above the floor whose support remains unresolved.

Every support element keeps its center, bounded footprint radius, min/max
world-Y extent, evidence refs, confidence, and resolved/uncertain state.

No symmetry completion is performed. Three observed table legs produce three
support elements; a fourth leg is never generated merely because a table is
expected to have one.

## Empty-space semantics

The preview distinguishes `sparseObservedSupports`, `solidToFloor`, and
`unresolved` lower-volume states. Sparse lower occupancy backed by observed
support columns prevents the preview from treating the whole body-to-floor
volume as one solid rectangular block.

This is deliberately not canonical free-space carving. Absence of mesh samples
alone is not treated as proof of empty space. If the body is observed above a
floor reference but no support element has enough evidence, the result is
`floatingBodyUnresolved`; the implementation does not fill the gap with a
solid box and does not invent invisible legs.

A bounded floor reference is derived from floor-classified live ARMesh faces
using a capped median sample. Table and seat classifications feed the furniture
support analysis, while wall observations remain on their existing path.

## Guidance seam

Support analysis emits typed advisory output rather than coupling directly to a
scanner-guidance implementation. The current advisory kinds are:

- `observeLowerFurniture`;
- `observeLowerFurnitureFromAnotherAngle`.

The scanner can render these as “show the lower part of the furniture” /
“show the lower part from another angle.” A future guidance authority can
consume the same typed output without making derived support geometry
canonical.

## Support preview rendering

Observed supports are rendered separately from the furniture footprint. The
existing orange derived body/footprint remains distinct from RoomPlan's white
semantic approximation, while support candidates use cyan markers. Uncertain
support candidates are thinner and dashed/translucent.

Heavy vertical segmentation and support clustering runs in the existing
detached utility task. The live main-actor path only performs bounded mesh
sampling and a capped floor-height sample; it does not serialize the full mesh
at UI cadence.

## Support-element automated acceptance

Synthetic fixtures cover:

- tabletop plus four visible legs;
- tabletop plus three visible legs with no invisible fourth-leg completion;
- pedestal table;
- solid cabinet reaching the floor;
- sofa body plus short supports;
- body floating above the floor with unresolved support evidence;
- isolated noisy points;
- insufficient height evidence.

Physical LiDAR acceptance remains a separate gate. The automated suite does not
claim that real-device occlusion, mesh classification, or RoomPlan presentation
quality has been validated.


## 3D object decomposition

Stacked or nearby observed geometry now preserves bounded world-Y evidence before
footprint fitting. A deterministic, bounded 3D decomposition can keep vertically
separated or weakly connected components distinct, expose preview-only support
relations, and request re-observation when component count remains ambiguous.

The detailed authority, performance bounds, synthetic fixtures, and physical
acceptance gate are documented in
[`DERIVED_OBJECT_DECOMPOSITION.md`](DERIVED_OBJECT_DECOMPOSITION.md).

Equal X/Z projection is not object-identity authority, and a sparse bridge does
not automatically merge otherwise separate observed components. Each resolved
component can independently enter the existing circle / ellipse / oriented
rectangle / polygon fitter. The decomposition remains preview-only and does not
promote a canonical object hierarchy.



## Scene-depth fallback when ARMesh anchors are absent

Physical testing showed that a RoomPlan scan may provide scene depth while the
active shared ARSession exposes zero ARMesh anchors. The previous derived-shape
path returned no observation in that case, so circle/ellipse fitting, support
analysis, and 3D decomposition could never run even though depth evidence was
available.

The live preview now has a bounded scene-depth fallback:

- sample `smoothedSceneDepth` when available, otherwise `sceneDepth`;
- reject invalid/out-of-range and low-confidence samples;
- unproject depth pixels with the exact ARFrame camera intrinsics and transform;
- preserve world-Y for support/decomposition analysis;
- cap the sampled point budget and apply deterministic 3D voxel reduction;
- estimate only a preview floor reference from observed depth distribution when
  classified mesh floor evidence is unavailable;
- tag every fallback observation as `scene_depth`.

For footprint fitting, dense scene-depth interior samples are reduced to a
radial outer-boundary observation before circle/ellipse/rectangle/polygon
selection. This is a derived-preview operation only. Raw scene depth remains
canonical only through the existing persisted frame/depth evidence package.

No semantic furniture label is inferred from depth. No unseen leg, chair curve,
wall, or object completion is generated. If the depth evidence remains
ambiguous, the existing unresolved/ambiguous states remain authoritative for
the preview.


## Multi-view curved-shape correction

Physical testing with a round table and curved chair showed that a flexible
polygon could remain the visible result even when a circle/ellipse was also a
credible candidate. The derived preview therefore adds two bounded corrections.

First, recent same-coordinate-space scene-depth observations are fused across a
small temporal window with deterministic 3D voxel deduplication. Re-observing an
object from another angle now contributes to the next preview instead of simply
replacing the previous single-frame observation.

Second, footprint fitting can prefer a strongly supported circle/ellipse over a
rectangle or many-vertex polygon when:

- the curved candidate has sufficient angular support;
- support score and residual pass explicit thresholds;
- its residual is close to the competing flexible model.

This is a model-selection preference, not semantic object recognition. A partial
arc, near-square rounded superellipse, or mixed circle/square evidence remains
unresolved or non-circular when the curved evidence is not strong enough.

For depth-backed furniture, the fitter also extracts a representative horizontal
slice before boundary fitting. Broad tabletop/seat/body evidence can therefore
drive the 2D footprint while lower legs/supports remain available to the separate
vertical support analysis instead of distorting the body outline.

Live-resource bounds remain explicit: temporal frame count, age, fused points,
depth/mesh sample counts, and face inspection are capped. The preview stays
derived/advisory and is never promoted to canonical room geometry.

Physical acceptance is still required for the actual round table, curved chair,
and complex non-rectangular furniture seen on device.
