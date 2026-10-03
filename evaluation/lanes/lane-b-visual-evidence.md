# lane-b — high-quality visual evidence (#275)

Protocol revision: **v2** (fixtures/metrics/decision sections filled; v1 was the initial scaffold)

Bounded **one-shot** high-resolution evidence stills as supplemental capture evidence (#275, PR #284). A still lands under `evidence/` as a declared payload with an advisory note — it supplements the live frame stream, never replaces it, and the high-res request is strictly bounded (one shot at a time, cooldown, busy/failure honesty). All camera-pipeline numbers in this lane are **device-gated**: they need iPhone-class hardware (target: iPhone 17 Pro). Software-side behavior (bound enforcement, persistence, advisory provenance, failure classification) is verified by `swift test` on macOS.

Compare only plausible profiles on the same tasks: default video format (baseline); one-shot high-res still (implemented); high-res-recommended format; 4K candidate; HDR off/on; default photo settings; manual tuning only if a concrete evidence failure motivates it. Never pick a profile just for larger RGB dimensions.

## Fixtures

- `label-far` — equipment label at increasing standoff distances; the deciding case for useful recognition distance vs the default stream.
- `label-glare` — glossy label under specular glare and mixed lighting; HDR on/off arms.
- `label-dark` — low-light label; noise vs usable OCR/barcode trade-off.
- `label-hicontrast` — high-contrast small print (silkscreen on metal), for mask-quality and OCR-accuracy arms.
- `busy-storm` — repeated still requests during an active scan to exercise the bound: busy/failure rates must be counted honestly, never dropped silently.
- `private_fixture: true` for in-situ runs — commit case manifest, protocol, and aggregates only.

## Metrics

### Numeric (device)

- `ocr_exact_char_accuracy` — exact-character OCR accuracy per profile across the label fixtures (canonical arm: the deterministic Vision OCR path in `App/EquipmentLabelVisionScan.swift`).
- `barcode_success_rate` — barcode decode success per profile/distance.
- `useful_recognition_distance_m` — max standoff where OCR/barcode still succeeds, per profile.
- `still_latency_s` / `still_size_bytes` / `still_write_cost` — capture→persist wall time, file size, and working-set admission cost per still.
- `hires_busy_rate` / `hires_failure_rate` — fraction of requests rejected as busy vs failed, under `busy-storm` and normal use.
- `frame_interval_ms` / `tracking_continuity` / `thermal_timeline` — AR cadence, tracking loss incidence, and thermal cost during and around a still capture vs baseline-0. Depth/RoomPlan degradation is a hard stop condition, not an average.

### Rate/count (software-verifiable now, macOS `swift test`)

- Bound enforcement: one still in flight at a time; concurrent/additional requests classify busy/failure honestly.
- Persistence: still bytes + descriptor declared in the manifest with capture provenance; advisory note recorded per still (`automaticKeyframe`/`highResolutionStill` kinds); the accumulated advisories doc rewrites across notes (regression-covered).
- Claimed RGB↔depth/pose relationships: any recorded relationship is stamped from real capture metadata — nothing fabricated.

### Failure categories (hard)

- `pipeline_disruption` — a still request measurably degrading AR frame cadence, tracking, or RoomPlan output beyond tolerance. Any occurrence fails the profile.
- `silent_drop` — a requested still that neither persists nor records a busy/failure classification.
- `integrity_breach` — still bytes/pose/timestamp inconsistent with the capture session it claims.

## Decision scope

Keep the one-shot high-res lane enabled if, on the device gate: it lifts `ocr_exact_char_accuracy`/`useful_recognition_distance_m` meaningfully on the label fixtures, leaves AR cadence/tracking/RoomPlan within tolerance, and keeps busy/failure rates low under realistic pacing. Stay on the default stream (roll back) if the gains are marginal, pipeline disruption is measurable, or busy/failure honesty forces the operator to retry manually. `experimental` remains the correct status until the first real-device campaign completes — no aggregate is claimed before then.
