# Binary Payload Formats v1

Status: Phase 0 contract

All binary payloads use explicit magic/version headers and little-endian scalar encoding. Implementations must reject unsupported versions.

## 1. Common header

Every HTDT-Capture binary payload begins with:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 8 | ASCII magic |
| 8 | 2 | major version, uint16 LE |
| 10 | 2 | minor version, uint16 LE |
| 12 | 4 | header byte length, uint32 LE |

No native Swift/Metal struct padding is serialized.

## 2. Mesh payload: `.meshbin`

Magic: `HTDTMSH1`

After the common header, the v1 logical sections are:

- vertex count, uint32;
- face count, uint32;
- index component width, uint8: 2 or 4 bytes;
- flags bitset for normals/classifications;
- positions: tightly packed xyz float32 meters;
- normals when present: tightly packed xyz float32;
- triangle indices: tightly packed uint16/uint32;
- classification bytes when present: one uint8 per face.

The anchor transform is not duplicated inside the geometry payload; it resides in `mesh/anchors.json` as `T_world_from_mesh_anchor`.

Source Metal/ARGeometry stride/offset metadata may be retained as metadata, but source buffer padding is never canonical payload.

## 3. Camera pixels: `.pixelbin`

Magic: `HTDTPXL1`

The associated frame JSON contains:

- pixel format/fourcc;
- plane count;
- native width/height;
- source row stride per plane;
- canonical packed row byte count;
- per-plane dimensions and payload offsets.

The binary file contains only defined active pixel bytes, row-by-row and plane-by-plane.

Allocator padding between active row bytes and source `bytesPerRow` is deliberately excluded.

For common bi-planar YCbCr input, luma and chroma planes remain separate and retain their pixel format semantics; HTDT-Capture does not silently convert them to RGB for canonical evidence.

## 4. Depth: `.depthbin`

Magic: `HTDTDPT1`

V1 depth payload:

- width, uint32;
- height, uint32;
- component type enum;
- tightly packed row-major depth values.

Preferred canonical component type is IEEE-754 float32 meters when that matches the ARDepthData depth-map interpretation.

No NaN/infinity is accepted as valid numeric evidence; invalid samples require an explicit validity policy/metadata rather than transport-level ambiguity.

## 5. Confidence: `.confidencebin`

Magic: `HTDTCNF1`

V1 confidence payload is one uint8 confidence code per depth sample, tightly packed row-major, with dimensions required to match its associated depth observation.

## 6. Hashing

The manifest SHA-256 is over the exact serialized binary payload bytes, including the format header.

## 7. Evolution

Adding fields that change byte interpretation requires a binary format version increment. A parser never guesses a format from file size.
