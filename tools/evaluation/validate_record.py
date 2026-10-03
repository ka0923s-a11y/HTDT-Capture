"""Validate evaluation-record JSON files against the v1 schema.

Dependency-free: reuses tools/bundle_validator/schema_eval.py.

Usage: python3 tools/evaluation/validate_record.py <record.json> [...]
Exits non-zero on the first invalid record.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from tools.bundle_validator.schema_eval import SchemaError, validate  # noqa: E402

SCHEMA_PATH = REPO_ROOT / "schemas" / "evaluation-record-v1.schema.json"


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    schema = json.loads(SCHEMA_PATH.read_text())
    ok = True
    for arg in argv[1:]:
        path = Path(arg)
        try:
            instance = json.loads(path.read_text())
            validate(instance, schema)
            print(f"{path}: valid")
        except (OSError, json.JSONDecodeError, SchemaError) as exc:
            print(f"{path}: INVALID — {exc}", file=sys.stderr)
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
