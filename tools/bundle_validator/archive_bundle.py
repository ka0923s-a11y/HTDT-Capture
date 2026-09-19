"""Reference .htdtcapture archive wrapper.

ZIP bytes are transport only. Logical identity remains the canonical
manifest digest validated by validator.py.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import uuid
import zipfile

from tools.bundle_validator.validator import ValidationError, validate_bundle


def create_archive(source: Path, destination: Path) -> dict:
    source = source.resolve()
    destination = destination.resolve()

    if not source.is_dir():
        raise ValidationError(f"source is not a directory: {source}")
    if destination.suffix != ".htdtcapture":
        raise ValidationError("destination must use .htdtcapture extension")
    if destination.exists():
        raise ValidationError(f"destination already exists: {destination}")

    source_report = validate_bundle(source)
    destination.parent.mkdir(parents=True, exist_ok=True)

    temp = destination.with_name(
        f".{destination.name}.tmp-{uuid.uuid4().hex}"
    )
    try:
        files = sorted(
            (
                path
                for path in source.rglob("*")
                if path.is_file()
            ),
            key=lambda path: path.relative_to(source).as_posix().encode("utf-8"),
        )

        with zipfile.ZipFile(
            temp,
            mode="x",
            compression=zipfile.ZIP_STORED,
            allowZip64=True,
        ) as archive:
            for path in files:
                relative = path.relative_to(source).as_posix()
                archive.write(path, arcname=relative)

        archive_report = validate_bundle(temp)
        if archive_report["bundle_digest"] != source_report["bundle_digest"]:
            raise ValidationError(
                "archive logical bundle digest differs from source directory"
            )

        os.replace(temp, destination)
        return archive_report
    except Exception:
        try:
            temp.unlink()
        except FileNotFoundError:
            pass
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Wrap a validated HTDT capture directory as .htdtcapture"
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args(argv)

    try:
        report = create_archive(args.source, args.destination)
    except (ValidationError, OSError) as exc:
        print(f"archive failed: {exc}", file=sys.stderr)
        return 2

    print(report["bundle_digest"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
