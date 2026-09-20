# Derived object decomposition

Status: software authority slice for preview-only object decomposition.

This slice addresses the failure mode where vertically separated or nearby
observed geometry is projected into one large X/Z footprint before derived
shape fitting. It does not perform semantic object recognition and it does not
promote a component graph into the Capture Bundle.

## Authority and data flow

The preview path is:

```text
bounded ARMesh observation
  -> X/Z position + preserved world Y
  -> bounded 3D density/connectivity segmentation
  -> component candidates + vertical extents
  -> optional preview-only support-relation candidates
  -> per-component existing footprint fitter
       (oriented rectangle / circle / ellipse / polygon)
  -> disclosure/review UI
```

RoomPlan and canonical capture evidence remain unchanged. Component identity,
support relations, object count, and re-observation advice are advisory derived
state only.

No semantic label such as "table", "box", or "object on table" is inferred by
the decomposition authority. A relation only says that a lower observed
component may support an upper observed component.

## Preserving height evidence

`DerivedObservationPoint` now preserves optional `verticalY` alongside its
existing X/Z footprint position. Mesh and live ARMesh extraction populate this
value before voxel reduction.

Voxel reduction is three-dimensional for points that contain Y evidence. This
prevents equal X/Z projection cells at different heights from silently
collapsing into one point.

Legacy/source-neutral observations without Y remain valid input to the shape
fitter, but object decomposition fails closed to an unresolved state and emits a
typed re-observation advisory rather than inventing component count.

## Bounded 3D segmentation

`DerivedObjectDecomposer` uses a deterministic, bounded DBSCAN-like expansion.

The live-preview configuration caps input at 512 points and at six component
candidates. Pairwise neighborhood analysis is therefore bounded. It considers:

- horizontal X/Z distance;
- vertical separation / adjacent height-band continuity;
- stronger connectivity evidence when two samples come from the same observed
  mesh element;
- local neighborhood support, so a sparse one-point/line bridge cannot expand
  a cluster by itself;
- component vertical extent and height ordering after segmentation.

The default ordinary vertical link is intentionally tighter than the horizontal
link. A visible vertical gap therefore remains a separation even when the X/Z
footprints overlap. Same-element mesh evidence can relax that vertical link in a
bounded way so genuinely continuous faces are not split merely because their
sample spacing is larger.

Sparse bridge samples may attach as border/noise observations but do not become
unconditional transitive merge authority. A narrow connector that has sustained
local observation density can still connect two regions.

## Component model

Each component candidate retains:

- deterministic component ID;
- original bounded `DerivedShapeObservation`;
- `minY`, `maxY`, vertical centroid, and vertical extent;
- bounded point count;
- lower-to-upper height ordering.

The existing derived footprint fitter is then called independently for each
resolved component. The decomposition API therefore does not assume one object
or one rectangle.

## Support relation candidates

For distinct components, the preview may emit a `supports` candidate when:

- the lower component centroid is below the upper component centroid;
- the vertical gap is within a bounded support window;
- their observed X/Z bounds overlap sufficiently.

This relation is preview-only geometry evidence. It is not a semantic statement
about furniture identity and is not persisted as canonical object hierarchy.

## Object-count uncertainty and re-observation

The typed decomposition state is one of:

- `resolved`;
- `possible_multiple_components`;
- `unresolved_decomposition`.

Insufficient Y evidence, significant unassigned/noise evidence, or bounded
analysis limits do not silently collapse to "one object". The result can carry a
`DerivedObjectReobservationAdvisory` with the bounded observed region so later
guided-scanning work can request another viewing angle without coupling this
slice to a specific guidance implementation.

The current disclosure UI shows component count, lower/upper (or layer) ordering,
height range, support-relation candidate count, and a compact "re-observe from
another angle" message when needed. The scanner camera remains the primary
surface; the details stay inside the existing observed-geometry disclosure.

## Performance

The existing scanner authority samples spatial state every 250 ms and runs
derived shape work only every fourth sample (approximately 1 Hz). Numerical
decomposition and fitting execute in the existing detached utility task, outside
the main actor.

The decomposition is bounded by:

- maximum 512 input points;
- maximum six component candidates;
- deterministic pairwise neighborhood analysis over that bounded set;
- no full-mesh clustering every frame;
- existing capped ARMesh face inspection and point reduction.

## Automated acceptance

Synthetic core fixtures cover:

- two vertically stacked boxes with a gap;
- broad touching support geometry;
- one continuous stepped object;
- two nearby boxes at the same height;
- a thin sparse/noisy bridge;
- a true dense narrow connector;
- overlapping X/Z footprints with vertical separation;
- insufficient/missing vertical evidence;
- deterministic output and compatibility with per-component shape fitting.

Repository pull-request CI remains responsible for `swift test`, generic iOS
platform/AppShell compilation, and the existing unsigned IPA workflow.

## Physical-device acceptance gate

Automated tests do not establish LiDAR behavior. Physical acceptance remains
open for:

- stacked rectangular objects resisting collapse into one giant footprint;
- different-height objects remaining distinct when observation supports that
  separation;
- continuous objects avoiding extreme over-segmentation;
- ambiguous regions producing useful re-observation advice;
- scanner frame rate / thermal behavior remaining acceptable.

No physical-device result is claimed by this software slice.
