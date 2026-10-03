# Reference-object training pipeline (legacy bolph71656-ai/HTDT-Capture#268)

Reproducible authority for every `.referenceobject` shipped in
`App/ReferenceObjects/`. Two artifacts:

- `training-manifest.json` — one entry per asset revision: source USDZ
  identity + digest + measured dimensions, resolved
  `xcrun createml objecttracker` arguments (mode, viewing angles,
  negative examples, `REFERENCEOBJECT_STRIP_USDZ` decision), toolchain,
  output digest, license provenance.
- `build_reference_object.py` — verifies source digests, renders the
  exact createml argv for an entry (dry-run default), and executes it
  with `--run`.

```sh
# See what would run for every declared asset
python3 tools/reference_object_training/build_reference_object.py

# Build one asset for real (needs the source USDZ present)
python3 tools/reference_object_training/build_reference_object.py \
    --asset <asset_id> --run
```

## Verified toolchain surface (Xcode 27 RC, iPhoneOS27.0.sdk)

`xcrun --toolchain com.apple.dt.toolchain.XcodeDefault createml objecttracker`:

| Flag | Meaning |
|------|---------|
| `-s/--source` | input `.usdz` (required) |
| `-o/--output` | output `.referenceobject` (required) |
| `-m/--training-mode` | `standard` (default) or `extended` — extended takes several times longer, recommended for high frame-rate tracking |
| `--front` / `--upright` / `--all-angles` | viewing-angle training domain (default `--upright`) — narrowest honest domain wins |
| `--objects-to-avoid` | negative-example USDZ, repeatable — add lookalikes that produce false matches |
| `--checkpoint` | checkpoint dir for resumable training |
| `--summary` / `--summary-fd` | training summary output |
| `--csv-progress` / `--csv-fd` | machine-readable progress |

`REFERENCEOBJECT_STRIP_USDZ=1` in the environment strips the USDZ embedded
in the artifact (a debugging aid for Create ML's viewer). Keep it on for
shipped assets unless the embedded USDZ is needed for inspection — record
the choice in `training.strip_usdz`.

## iOS 27 runtime contract this feeds

- `ARWorldTrackingConfiguration.detectionObjects` (stationary fixtures)
  and `trackingObjects` (movable/handheld) accept `.referenceobject`
  assets; combined cap is **10 files**.
- Legacy `.arobject` works only with detection and **cannot mix** with
  `.referenceobject` in the same session — the app loader rejects
  `.arobject` outright.
- `trackingObjects` raises processing/power load; request it per asset
  only when the object actually moves.

## Revision discipline

A retrained artifact is a **new revision** — bump `asset_revision` in the
manifest, update `output.sha256`, and ship it under the same `asset_id`.
Never reinterpret observations recorded against an older digest: the
app-side `App/ReferenceObjects/manifest.json` declares the same
`(asset_id, revision, artifact digest)` tuple, and persisted
`ReferenceObjectPoseObservation` records carry it verbatim.

## After training

1. Move the artifact to `App/ReferenceObjects/<arkit_object_name>.referenceobject`.
2. Write `output.sha256` here and `artifact digest` + `revision` in
   `App/ReferenceObjects/manifest.json`.
3. The name ARKit reports on `ARObjectAnchor.referenceObject.name` is
   the file base name — it must equal `arkit_object_name` so the adapter
   can map the match back to the manifest entry.
