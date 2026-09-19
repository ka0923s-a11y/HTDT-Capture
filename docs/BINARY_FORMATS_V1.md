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

After the 16-byte common prefix, the implemented v1 mesh header is:

| Offset | Size | Field |
|---:|---:|---|
| 16 | 4 | vertex count, uint32 LE |
| 20 | 4 | face count, uint32 LE |
| 24 | 1 | index component width |
| 25 | 1 | flags: bit 0 normals, bit 1 classifications |
| 26 | 2 | reserved, zero |
| 28 | 4 | reserved, zero |

The implemented encoder emits index component width `4` (UInt32). The decoder rejects other widths for v1 rather than guessing.

Payload order after byte 31:

- positions: tightly packed xyz float32 meters;
- normals when flag bit 0 is present: tightly packed xyz float32;
- triangle indices: tightly packed uint32 LE;
- classification bytes when flag bit 1 is present: one uint8 per face.

The anchor transform is not duplicated inside the geometry payload; it resides in `mesh/anchors.json` as `T_world_from_mesh_anchor`.

The current v1 decoder requires the common-header `header byte length` to equal 32 for mesh payloads and rejects trailing bytes.

Source Metal/ARGeometry stride/offset metadata may be retained as metadata, but source buffer padding is never canonical payload.

## 3. Camera pixels: `.pixelbin`

Magic: `HTDTPXL1`

The fixed header is 32 bytes:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 8 | magic |
| 8 | 2 | major version uint16 LE |
| 10 | 2 | minor version uint16 LE |
| 12 | 4 | total header byte length uint32 LE |
| 16 | 4 | full image width uint32 LE |
| 20 | 4 | full image height uint32 LE |
| 24 | 4 | CoreVideo pixel-format FourCC uint32 LE |
| 28 | 2 | plane count uint16 LE |
| 30 | 2 | reserved, zero |

Each plane then contributes a 24-byte descriptor inside the header:

| Relative | Size | Field |
|---:|---:|---|
| +0 | 4 | plane width uint32 LE |
| +4 | 4 | plane height uint32 LE |
| +8 | 4 | source bytes-per-row uint32 LE |
| +12 | 4 | canonical packed bytes-per-row uint32 LE |
| +16 | 4 | absolute payload offset uint32 LE |
| +20 | 4 | payload byte count uint32 LE |

Therefore:

```text
header_length = 32 + plane_count * 24
```

Plane payloads immediately follow the descriptor table in descriptor order, with no gaps.

Canonical pixel payload rules:

- only defined active row bytes are copied;
- source allocator padding is excluded;
- source row stride is retained as metadata only;
- plane payload byte count must equal `height * packed_bytes_per_row`;
- payload offsets must be contiguous;
- trailing bytes are rejected.

The current iOS adapter formally supports:

- `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`;
- `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`;
- `kCVPixelFormatType_32BGRA`.

For bi-planar 4:2:0, luma is packed at one byte per plane pixel and interleaved chroma at two bytes per plane pixel. Unknown formats fail closed rather than being converted heuristically.

## 4. Depth: `.depthbin`

Magic: `HTDTDPT1`

The v1 header is 32 bytes:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 8 | magic |
| 8 | 2 | major version uint16 LE |
| 10 | 2 | minor version uint16 LE |
| 12 | 4 | header length uint32 LE = 32 |
| 16 | 4 | width uint32 LE |
| 20 | 4 | height uint32 LE |
| 24 | 1 | component type = 1, float32 meters |
| 25 | 1 | flags; bit 0 = validity mask present |
| 26 | 2 | reserved, zero |
| 28 | 4 | reserved, zero |

Payload order:

1. tightly packed row-major IEEE-754 float32 depth values in meters;
2. when flag bit 0 is present, one uint8 validity value per depth sample.

Validity values are exactly `0` or `1`.

Non-finite source depth values are not serialized as NaN/infinity. The iOS adapter serializes numeric zero for that sample and sets validity to `0`, preserving the fact that the source sample was invalid without making transport interpretation depend on NaN payload semantics.

Finite zero is not automatically declared invalid; the adapter does not invent an ARKit validity policy beyond finite/non-finite transport normalization.

## 5. Confidence: `.confidencebin`

Magic: `HTDTCNF1`

The v1 header is 32 bytes:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 8 | magic |
| 8 | 2 | major version uint16 LE |
| 10 | 2 | minor version uint16 LE |
| 12 | 4 | header length uint32 LE = 32 |
| 16 | 4 | width uint32 LE |
| 20 | 4 | height uint32 LE |
| 24 | 1 | component type = 1, uint8 confidence code |
| 25 | 1 | reserved, zero |
| 26 | 2 | reserved, zero |
| 28 | 4 | reserved, zero |

The payload is exactly one uint8 code per depth sample, tightly packed row-major.

The iOS adapter requires the confidence map dimensions to equal the corresponding depth map dimensions. Confidence codes are preserved without remapping so downstream logic can interpret them against the recorded ARKit/runtime provenance.

## 6. Hashing

The manifest SHA-256 is over the exact serialized binary payload bytes, including the format header.

## 7. Evolution

Adding fields that change byte interpretation requires a binary format version increment. A parser never guesses a format from file size.
