# Spatial Accuracy Validation Protocol

Status: Phase 0 provisional engineering protocol  
Related issue: #9

## 1. Purpose

HTDT-Capture does not assign a universal accuracy value to Apple LiDAR hardware. Spatial performance is validated for the actual device/OS/app/configuration/trajectory used by the product.

This protocol produces engineering evidence. It is not a marketing accuracy claim.

## 2. Reference environment

The initial benchmark should include:

- a small room or rigid test area with independently measured wall/reference distances;
- at least three known planar surfaces;
- at least five known 3D reference points spanning the capture volume;
- one speaker-sized object/reference marker with known orientation;
- a closed-loop walking path;
- transparent/reflective surfaces documented separately rather than mixed into the nominal fixture.

Reference distances should use a calibrated or traceable laser distance meter where available. Instrument model, calibration status/date, and stated tolerance are recorded.

## 3. Repetition

Minimum initial run set:

- 5 complete scans by one operator;
- 2 operators when practical, at least 3 scans each;
- identical target app build and exact AR configuration;
- raw observations preserved even if a run fails thresholds.

## 4. Metrics

### Dimension error
For each reference distance:

```text
error = observed - reference
absolute_error = abs(error)
```

Report mean signed bias, median absolute error, RMSE, and P90 absolute error.

### Plane residual
Fit a plane to the relevant reconstructed surface samples and report RMS orthogonal residual plus P90 residual.

### Drift / loop closure
Measure displacement of stable start/end reference geometry after the closed-loop trajectory.

### RoomPlan-to-mesh agreement
Measure signed/absolute distance between corresponding RoomPlan surfaces and ARMesh geometry after expressing both in the declared shared coordinate space.

### Annotation repeatability
For repeated placement of the same known reference point, report 3D standard deviation and P90 pairwise displacement.

### Orientation repeatability
Report angular error/repeatability for known speaker-forward orientation.

### Depth by range/confidence
Bin depth observations by range and confidence code, then report bias/RMSE/count per bin.

## 5. Provisional internal thresholds

These are Phase 0 engineering gates, not public claims. Failure causes investigation or explicit threshold revision with rationale.

For nominal opaque indoor surfaces and reference dimensions up to 5 m:

- dimension P90 absolute error: <= 50 mm;
- dimension RMSE: <= 40 mm;
- fitted-plane RMS residual: <= 25 mm;
- closed-loop drift at the reference marker: <= 100 mm;
- RoomPlan-to-mesh corresponding-surface median absolute offset: <= 50 mm;
- annotation placement P90 repeatability: <= 50 mm;
- speaker orientation P90 repeatability: <= 5 degrees.

Depth accuracy is initially characterization-only by range/confidence bucket. A hard depth threshold is set only after the first device baseline because the capture mode may differ from RoomPlan scanning.

## 6. Critical-dimension rule

Any downstream dimension whose required tolerance is tighter than the demonstrated scan performance must be represented by a higher-confidence independent measurement authority.

For the MVP, dimensions requiring better than approximately 50 mm positional tolerance or approximately 5 degrees orientation tolerance should prompt a user-attested external measurement rather than silently relying on scan geometry.

## 7. Capture protocol

- use the app's documented range/coaching guidance;
- avoid rapid motion;
- preserve sufficient visual overlap;
- complete a closed loop where practical;
- record tracking-state degradation;
- record thermal/resource interruptions;
- do not delete failed evidence.

## 8. Required provenance

Every benchmark report records:

- device model;
- OS version;
- app version/build;
- exact AR configuration;
- RoomPlan configuration;
- capture mode;
- capture-session and coordinate-space IDs;
- operator/run identity that does not expose unnecessary personal data;
- reference instrument metadata;
- reference geometry revision.

## 9. Promotion rule

A threshold or product claim may only be strengthened when preserved benchmark evidence supports it.

Changing thresholds to make a failed run pass is prohibited unless the threshold revision is documented with engineering rationale and historical results remain visible.
