# Phase 2 RoomPlan + Mesh Evidence Implementation Record

Status: In progress  
Issue: #3

## Implemented in this slice

- Separate raw RoomPlan and postprocessed RoomPlan evidence descriptors.
- Explicit processed -> raw SHA-256 lineage.
- Shared capture-session and coordinate-space authority on both RoomPlan evidence layers.
- Runtime provenance record.
- Portable mesh anchor snapshot model.
- Column-major `T_world_from_mesh_anchor` representation.
- Mesh geometry validation:
  - finite vertex/normal values;
  - matching normal count;
  - triangle-only indices;
  - index bounds;
  - classification count.
- Versioned `.meshbin` reference codec.
- iOS RoomPlan Codable artifact encoder.
- iOS ARMeshAnchor adapter that:
  - interprets geometry source offset/stride;
  - copies active float3 vertex/normal values;
  - normalizes index data to UInt32;
  - preserves per-face raw ARKit classification bytes;
  - does not serialize MTLBuffer padding.
- Round-trip mesh codec tests.

## Canonical mesh binary layout implemented

`HTDTMSH1`, version 1.0:

- bytes 0-7: magic `HTDTMSH1`;
- bytes 8-9: major version uint16 LE;
- bytes 10-11: minor version uint16 LE;
- bytes 12-15: header length uint32 LE = 32;
- bytes 16-19: vertex count uint32 LE;
- bytes 20-23: face count uint32 LE;
- byte 24: index component width; encoder emits 4;
- byte 25: flags, bit 0 normals, bit 1 classifications;
- bytes 26-27: reserved uint16 = 0;
- bytes 28-31: reserved uint32 = 0;
- then tightly packed xyz float32 positions;
- optional tightly packed xyz float32 normals;
- UInt32 triangle indices;
- optional one-byte-per-face classification channel.

The decoder rejects unsupported versions/index widths/flags, invalid geometry, truncation, and trailing bytes.

## Not yet complete

The following remain hardware-gated:

- acquire a real `CapturedRoomData` from RoomPlan and persist/reopen it;
- regenerate a real `CapturedRoom` from preserved raw data;
- acquire real ARMeshAnchor snapshots during the same RoomPlan-owned world frame;
- prove RoomPlan/mesh alignment on reference geometry;
- collect the Issue #9 physical accuracy benchmark;
- prove session/world resets generate explicit coordinate lineage in real interruption cases.

Issue #3 must remain open until those are demonstrated.
