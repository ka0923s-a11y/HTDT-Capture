# HTDT-Capture Spatial Accuracy Validation Protocol

Status: Engineering protocol v1.0.0
Related issue: #9

## 1. Purpose

HTDT-Capture does not assign a universal accuracy value to Apple LiDAR hardware.
Spatial performance is validated for the exact device, OS, app build, AR
configuration, capture trajectory, room/reference fixture, and analysis ruleset
used by the product.

This protocol produces engineering evidence. It is not a marketing accuracy claim.

## 2. Evidence model

Raw benchmark observations are the evidence authority. Derived metrics and gate
results are reproducible interpretations under a named ruleset. They never
replace, edit, or suppress the raw observations.

Failed and interrupted runs remain preserved. A failed threshold triggers
engineering review or an explicitly versioned threshold revision with rationale.

## 3. Reference environment

The first real-device benchmark should include:

- independently measured room/reference dimensions;
- at least three known planar surfaces;
- at least five known 3D reference points spanning the capture volume;
- a speaker/reference marker with known position and forward orientation;
- a closed-loop scan route returning near the start location;
- depth references spanning the intended working range;
- transparent/reflective/problem surfaces documented separately.

Reference geometry should use a trustworthy independent instrument. Record
instrument class, make/model, calibration status/date, and stated uncertainty.

## 4. Repetition

Target initial run set:

- 5 complete scans by one operator;
- 2 operators when practical, at least 3 scans each;
- identical target app build and exact AR configuration;
- raw observations preserved even when a run fails.

The v1 analysis gate requires at least 3 comparable repeats for repeatability.
Five repeats remain the preferred physical baseline.

## 5. Capture procedure

1. Record device model/capability profile, OS, app version/build, and exact AR
   configuration-profile hash.
2. Record RoomPlan/reconstruction settings and reference instrument metadata.
3. Record independent reference values before reviewing HTDT-Capture errors.
4. Follow the declared closed-loop trajectory and coaching guidance.
5. Do not reset the AR world origin mid-run unless the run is explicitly
   classified as restarted/failed.
6. Preserve RoomPlan, ARMesh, selected frame/depth evidence, annotations,
   tracking/resource diagnostics, and benchmark observations for every run.
7. Preserve failed/interrupted runs with their failure state.

## 6. Metrics

### 6.1 Dimensions

For each sample: error = observed - reference.

Report maximum absolute error, signed bias, and RMSE.

### 6.2 Repeatability

For repeated observations of the same quantity, report population standard
deviation. Fewer than the configured minimum repeats yields insufficient_data,
not pass.

### 6.3 Plane residual

For signed point-to-reference-plane residuals, report signed bias and RMSE.
Outliers must not be silently removed; any outlier policy requires a separately
versioned method.

### 6.4 RoomPlan-to-ARMesh alignment

For matched points expressed in the same coordinate_space_id, compute Euclidean
separation and report RMSE/max error. Different coordinate spaces require an
explicit alignment authority before comparison.

### 6.5 Loop closure / drift

Compute Euclidean displacement between the recorded start and end positions of
the closed-loop route in the same coordinate space.

### 6.6 Annotation position repeatability

For repeated placements of the same marker, compute the centroid and RMSE of
placement distance from that centroid. This is repeatability, not absolute
accuracy unless an independent marker position is supplied.

### 6.7 Speaker orientation

Normalize reference and observed front vectors, clamp their dot product to
[-1, 1], and report angular error in degrees.

### 6.8 Depth

Preserve independent reference distance, observed depth, confidence code, and
frame/session lineage where available. Report signed bias, MAE, RMSE and sample
count by range bucket, plus confidence-code counts.

## 7. Provisional engineering ruleset

The repository ruleset engineering-provisional-1 is an internal design gate.
It is not a measured device specification or a product claim.

| Metric | Provisional gate |
|---|---:|
| Dimension max absolute error | <= 0.030 m |
| Dimension RMSE | <= 0.020 m |
| Repeatability population SD | <= 0.015 m |
| Plane residual RMSE | <= 0.015 m |
| RoomPlan-to-ARMesh alignment RMSE | <= 0.025 m |
| Loop-closure error | <= 0.030 m |
| Annotation position repeatability RMSE | <= 0.020 m |
| Speaker orientation max error | <= 3.0 deg |
| Depth RMSE, 0-1 m | <= 0.025 m, >= 3 samples |
| Depth RMSE, 1-2 m | <= 0.035 m, >= 3 samples |
| Depth RMSE, 2-3 m | <= 0.050 m, >= 3 samples |
| Depth RMSE, 3-5 m | <= 0.080 m, >= 3 samples |

These gates supersede the older Phase 0 placeholder thresholds for new v1
reports. Historical evidence remains visible with the ruleset that evaluated it.
Changing a threshold requires a new ruleset version and engineering rationale.

## 8. Result states

Each thresholded metric is pass, fail, or insufficient_data.

Overall status is fail if any gate fails; otherwise insufficient_data if any
required gate lacks evidence; otherwise pass.

A pass under this provisional ruleset does not authorize a public accuracy claim.

## 9. Critical-dimension rule

Any downstream dimension whose required tolerance is tighter than demonstrated
scan performance must use a higher-confidence independent measurement authority.
User-attested external measurements remain distinct from RoomPlan/ARKit inference.

## 10. Product-claim rule

No product accuracy claim may be promoted solely from the synthetic fixture, a
single device/run, a vendor hardware specification, or a provisional gate pass.
A claim requires preserved real-device evidence covering the claimed population,
plus explicit review of uncertainty, repeatability, failure cases, and scope.

## 11. Repository artifacts

- Observations schema: schemas/accuracy-benchmark-observations-v1.schema.json
- Ruleset schema: schemas/accuracy-benchmark-ruleset-v1.schema.json
- Report schema: schemas/accuracy-benchmark-report-v1.schema.json
- Analyzer: tools/accuracy_benchmark/analyze.py
- Synthetic fixture: samples/accuracy-benchmark/
