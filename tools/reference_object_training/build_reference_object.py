#!/usr/bin/env python3
"""Build a .referenceobject artifact from the training manifest (issue bolph71656-ai/HTDT-Capture#268).

Reads tools/reference_object_training/training-manifest.json, verifies the
source USDZ digest, resolves the `xcrun createml objecttracker` command line
from the manifest's declared training parameters, and either prints it
(--dry-run, the default) or executes it (--run). No asset training happens in
CI — this is the reproducible-invocation authority: every shipped
.referenceobject must be regenerable from the manifest entry that declares it.

After a successful --run, the script prints the output artifact's SHA-256 so
the operator can write it into both this manifest (`output.sha256`) and the
app-side `App/ReferenceObjects/manifest.json` provenance manifest. A retrained
asset is a NEW revision — bump `asset_revision`; never reinterpret evidence
recorded against an older digest.

Usage:
    python3 tools/reference_object_training/build_reference_object.py \\
        --asset <asset_id> [--run]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
MANIFEST_PATH = Path(__file__).resolve().parent / "training-manifest.json"

CREATEML_INVOCATION = (
    "xcrun --toolchain com.apple.dt.toolchain.XcodeDefault createml"
)
VIEWING_ANGLE_FLAGS = {
    "front": "--front",
    "upright": "--upright",
    "all-angles": "--all-angles",
}
SHA256_RE_LEN = 64


class ManifestError(Exception):
    """Raised when a manifest entry cannot produce a valid command line."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_manifest(path: Path) -> dict:
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ManifestError(f"cannot load {path}: {exc}") from exc
    if data.get("schema") != "htdt.reference-object-training":
        raise ManifestError(
            f"{path}: unexpected schema {data.get('schema')!r}"
        )
    return data


def resolve_command(asset: dict, manifest: dict) -> tuple[list[str], dict]:
    """Map one manifest entry onto the createml objecttracker argv + env."""
    required = (
        "asset_id",
        "asset_revision",
        "arkit_object_name",
        "supported_roles",
        "physical_binding",
        "source_usdz",
        "training",
        "output",
        "license_provenance",
    )
    missing = [key for key in required if key not in asset]
    if missing:
        raise ManifestError(
            f"asset {asset.get('asset_id')!r} missing keys: {missing}"
        )

    training = asset["training"]
    mode = training.get("mode")
    if mode not in ("standard", "extended"):
        raise ManifestError(
            f"{asset['asset_id']}: training.mode must be "
            f"standard|extended, got {mode!r}"
        )
    angles = training.get("viewing_angles")
    if angles not in VIEWING_ANGLE_FLAGS:
        raise ManifestError(
            f"{asset['asset_id']}: viewing_angles must be one of "
            f"{sorted(VIEWING_ANGLE_FLAGS)}, got {angles!r}"
        )

    source = REPO_ROOT / asset["source_usdz"]["path"]
    output = REPO_ROOT / asset["output"]["path"]

    argv = CREATEML_INVOCATION.split() + [
        "objecttracker",
        "--source", str(source),
        "--output", str(output),
        "--training-mode", mode,
        VIEWING_ANGLE_FLAGS[angles],
        "--summary",
    ]
    for avoid in training.get("objects_to_avoid", []):
        avoid_path = REPO_ROOT / avoid["path"]
        argv += ["--objects-to-avoid", str(avoid_path)]

    # REFERENCEOBJECT_STRIP_USDZ strips the source USDZ embedded in the
    # artifact (it is only a debugging aid in Create ML viewer). Stripped
    # artifacts are smaller; keep the decision explicit per asset.
    env = dict(os.environ)
    if training.get("strip_usdz"):
        env["REFERENCEOBJECT_STRIP_USDZ"] = "1"

    return argv, env


def verify_source(asset: dict) -> list[str]:
    """Check the source USDZ exists and matches its declared digest."""
    problems: list[str] = []
    source = REPO_ROOT / asset["source_usdz"]["path"]
    declared = asset["source_usdz"].get("sha256", "")
    if not source.exists():
        problems.append(f"source USDZ missing: {source}")
        return problems
    if len(declared) == SHA256_RE_LEN:
        actual = sha256_file(source)
        if actual != declared:
            problems.append(
                f"source USDZ digest mismatch for {source}:\n"
                f"  declared {declared}\n  actual   {actual}\n"
                f"  (retrained sources are new revisions — update the "
                f"manifest, never reuse the old digest)"
            )
    for avoid in asset["training"].get("objects_to_avoid", []):
        path = REPO_ROOT / avoid["path"]
        if not path.exists():
            problems.append(f"negative-example USDZ missing: {path}")
        elif len(avoid.get("sha256", "")) == SHA256_RE_LEN:
            actual = sha256_file(path)
            if actual != avoid["sha256"]:
                problems.append(
                    f"negative-example digest mismatch: {path}"
                )
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=MANIFEST_PATH,
        help="training manifest path (default: alongside this script)",
    )
    parser.add_argument(
        "--asset",
        action="append",
        help="asset_id to build; repeatable. Default: all assets.",
    )
    parser.add_argument(
        "--run",
        action="store_true",
        help="execute createml (default is a dry run that prints argv)",
    )
    args = parser.parse_args()

    try:
        manifest = load_manifest(args.manifest)
    except ManifestError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    assets = manifest.get("assets", [])
    if args.asset:
        wanted = set(args.asset)
        assets = [a for a in assets if a.get("asset_id") in wanted]
        missing = wanted - {a.get("asset_id") for a in assets}
        if missing:
            print(
                f"error: unknown asset_id(s): {sorted(missing)}",
                file=sys.stderr,
            )
            return 2
    if not assets:
        print("no assets to build", file=sys.stderr)
        return 1

    rc = 0
    for asset in assets:
        asset_id = asset.get("asset_id", "<unnamed>")
        print(f"== {asset_id} (revision {asset.get('asset_revision')})")

        try:
            argv, env = resolve_command(asset, manifest)
        except ManifestError as exc:
            print(f"   error: {exc}", file=sys.stderr)
            rc = 1
            continue

        problems = verify_source(asset)
        for problem in problems:
            print(f"   warning: {problem}", file=sys.stderr)

        rendered = " ".join(argv)
        if env.get("REFERENCEOBJECT_STRIP_USDZ"):
            rendered = "REFERENCEOBJECT_STRIP_USDZ=1 " + rendered
        print(f"   argv: {rendered}")

        if not args.run:
            print("   (dry run — pass --run to execute)")
            continue
        if problems:
            print("   skipped: fix source problems first", file=sys.stderr)
            rc = 1
            continue

        output_path = REPO_ROOT / asset["output"]["path"]
        output_path.parent.mkdir(parents=True, exist_ok=True)
        completed = subprocess.run(argv, env=env)
        if completed.returncode != 0:
            print(
                f"   createml exited {completed.returncode}",
                file=sys.stderr,
            )
            rc = 1
            continue
        digest = sha256_file(output_path)
        print(f"   wrote {output_path}")
        print(f"   output.sha256 = {digest}")
        print(
            "   next: record this digest in training-manifest.json "
            "(output.sha256) and App/ReferenceObjects/manifest.json "
            "(artifact digest). A retrained artifact is a NEW revision."
        )
    return rc


if __name__ == "__main__":
    sys.exit(main())
