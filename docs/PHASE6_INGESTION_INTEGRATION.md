# Phase 6 HTDT Ingestion Integration Record

Status: In progress  
Issue: #7

## Implemented in this slice

The repository now contains a deterministic reference ingestor for the
Capture Bundle v1 -> HTDT source-authority boundary.

The reference implementation intentionally stops before
`SemanticAcousticGeometry`. It produces a versioned ingestion plan that
can be consumed by the HTDT backend.

### Validation boundary

`.htdtcapture` input remains untrusted until the existing bundle validator
passes all archive/path/canonical-manifest/length/hash checks.

No source record or downstream handoff is produced before that succeeds.

### Source evidence registry

Every manifest payload becomes a deterministic source-evidence record
retaining:

- logical `bundle_digest`;
- capture revision ID;
- exact logical path;
- exact payload SHA-256 and byte length;
- media type and producer;
- provenance class;
- canonical/derived role;
- source references.

### RawVisualMesh handoff

`mesh/anchors.json` is interpreted as the anchor-level spatial authority.

For each anchor the ingestion plan retains:

- anchor UUID;
- exact anchor-record locator;
- exact anchor-index source evidence ID;
- exact `.meshbin` source evidence ID/path/SHA-256;
- capture-session ID;
- coordinate-space ID;
- `T_world_from_mesh_anchor`;
- observation timestamp;
- vertex/face counts.

The handoff does not fuse or repair mesh geometry.

### Authority-record handoff

Annotation and measurement records receive deterministic handoff IDs while
retaining their original record IDs, source payload hashes, coordinate-space
identity, and provenance class.

User annotations and user-attested measurements therefore remain distinct
from Apple RoomPlan inference, ARKit reconstruction, and future backend
derivation.

### Deterministic identity

IDs are SHA-256 domain-separated hashes over exact pinned inputs:

`source_evidence_id = H(domain, bundle_digest, path, payload_sha256)`

`raw_visual_mesh_handoff_id = H(domain, bundle_digest, anchor_id, mesh_sha256)`

`authority_record_handoff_id = H(domain, bundle_digest, source_payload_sha256, record_kind, record_id)`

The overall `lineage_digest` commits to the bundle digest and the sorted
deterministic handoff IDs.

These are deterministic content/lineage identifiers, not signatures.

### Frozen integration fixture

`samples/phase6-integration` contains:

- raw RoomPlan fixture evidence;
- postprocessed RoomPlan fixture evidence linked to the raw hash;
- one valid v1 mesh binary and one exact anchor record;
- one speaker annotation;
- one user-attested room-width measurement;
- canonical manifest.

Frozen logical bundle digest:

`925108a1b3c1b432182efe1b7e18ccb0f1d98f4f17c939ca66a6095b0cc28550`

Frozen lineage digest for ingestor v1.0.0:

`729a7590fb1d1e2142c196187ef11a9078522326daa1ef2fd2364b8fd1ef6bf1`

### CI verification

Phase 6 CI verifies:

- integration schemas parse;
- frozen bundle digest;
- repeat ingestion is byte-identical at canonical plan level;
- directory and `.htdtcapture` archive produce the same ingestion plan;
- RoomPlan/ARKit/user provenance classes remain distinguishable;
- RawVisualMesh handoff points to exact anchor-level mesh evidence;
- unknown coordinate references fail closed even when manifest hashes are valid;
- payload tampering fails before ingestion begins.

## Remaining integration work

This repository owns the capture-side/reference contract. Production HTDT
backend code still needs to consume this ingestion plan (or an equivalent
contract) transactionally and bind the resulting evidence records to HTDT's
native source-evidence / RawVisualMesh repositories.

That production backend adapter should be implemented in the HTDT backend
repository, not duplicated into the iPhone capture app.
