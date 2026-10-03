# lane-a — source-quality preflight (#277)

Protocol revision: **v1** (initial scaffold)

Staged physical cases: clean lens; light fingerprint/smudge; heavy haze/smudge; motion blur; naturally blurred content; dark theater; bright display in dark room; low-texture surfaces.

Metrics: smudge true/false positive rates; warning threshold behavior; stable-frame acquisition latency; nuisance warning rate; optional low-light advisory correlation with downstream OCR/evidence/tracking; added operator time.

Light estimates stay contextual/advisory — no single `ambientIntensity` threshold defines a valid scan.
