# lane-f — Core AI prototype (#271)

Protocol revision: **v1** (initial scaffold)

Gated on the #271 stop/go prerequisite — no large dataset before that. For the minimal prototype compare against manual/native/reference-object baselines.

Metrics: operator time saved; precision/recall/false positives; mask/detection quality; spatially supported candidate success; model/app/cache size; first specialization/load cost; steady latency/memory; thermal/battery/capture impact.

If the prototype is rejected: archive the result and stop expanding this lane.

## Stop/go gap analysis (v1, code-level)

The issue's own stop rule: build a custom-model lifecycle only if a
material gap remains after the existing paths plus #268/#269/#270.
Current disposition of each prerequisite:

| Prerequisite path | Status | Gap it already covers |
|---|---|---|
| Manual + targeted workflows | shipped | Operator-directed small-object pass (5–30 cm targeted objects), manual evidence stills, annotation/measurement workspace |
| #268 reference-object tracking | implemented (PR, device-gated) | Unattended rediscovery/tracking of *known* equipment + fixtures |
| #269 Vision iterative segmentation + depth fusion | implemented (PR, device-gated) | Operator-selected arbitrary-object masks + spatial extent without a custom model |
| #270 identity assist (Foundation Models) | implemented (PR, availability-gated) | Label/serial/model candidate ranking + catalog binding with operator confirmation |
| #275 hi-res evidence stills | implemented (PR, device-gated) | Bounded high-resolution visual/OCR evidence |

A custom Core AI detector/segmenter would add exactly two things the
stack does not provide:

1. **Unattended object discovery** — proposing spatially-grounded
   candidates the operator did not point at.
2. **Semantic room/equipment classification** beyond OCR/catalog text.

Neither is demonstrated necessary for the current operator-driven
capture workflow: every acquisition path above is deliberate
(operator-selected or operator-confirmed), which is the product's
authority model — a model proposing entities the operator never
targeted also carries the highest `authority_violation` risk class in
the record contract.

**Disposition (v1): `not_planned` unless** lane-c (#268), lane-d
(#269), or lane-e (#270) physical-device records measure a residual
gap the deterministic/native paths cannot close. The two candidate
additions above are the only gaps worth re-checking after those
records land; a prototype, if ever justified, deploys in the audited
order — bundled `.aimodel` first, `coreai-build` AOT assets second,
Background Assets only if the first two prove insufficient.

This is a code-level analysis, not a lane run — no evaluation record
is filed for v1 because every remaining question is device-evidence
gated (no simulator path can specialize a model or measure
thermal/latency honestly). Revisit when lane-c/d/e produce records.
