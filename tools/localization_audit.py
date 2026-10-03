#!/usr/bin/env python3
"""Localization audit for HTDT Capture (issue bolph71656-ai/HTDT-Capture#399).

Enforces the single Apple-native localization authority:

* every user-visible string literal extracted from Swift sources under
  ``App/`` and ``Sources/`` must have an entry in
  ``App/ja.lproj/Localizable.strings`` (English source text is the key);
* format-aware templates keep specifier parity between the key and the
  Japanese value;
* no production path may reintroduce a hand-rolled bilingual helper
  (``HostLocalization``) or infer UI language from
  ``Locale.preferredLanguages`` — ``String(localized:)`` follows the
  resolved bundle localization, which IS the authority.

Extraction covers ``String(localized:)`` and the SwiftUI label-style
initializers/modifiers that take a ``LocalizedStringKey``
(``Text``, ``Button``, ``Picker``, ``Section``, ``Label``,
``Toggle``, ``TextField``, ``SecureField``, ``Menu``, ``ControlGroup``,
``DisclosureGroup``, ``LabeledContent``, ``Tab``,
``.navigationTitle``, ``.searchable(prompt:)``,
``.confirmationDialog``, ``.alert``, ``.help``).

Literals containing ``\\(…)`` interpolation produce pattern keys whose
``\\(…)`` fragments are normalized to ``*``; a catalog key matches when
its own specifier-normalized form (``%@``, ``%lld``, ``%d`` …) is
identical. Missing entries, arity mismatches, duplicate keys, malformed
catalog lines, and forbidden patterns all fail the audit.

Run from the repo root: ``python3 tools/localization_audit.py``.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPO_ROOT / "App" / "ja.lproj" / "Localizable.strings"
SCAN_ROOTS = (REPO_ROOT / "App", REPO_ROOT / "Sources")

# ---- forbidden constructs -------------------------------------------------

FORBIDDEN = [
    (
        re.compile(r"\bHostLocalization\b"),
        "HostLocalization is removed; use String(localized:)",
    ),
    (
        re.compile(r"\bLocale\.preferredLanguages\b"),
        "manual preferredLanguages inference is forbidden; "
        "String(localized:) follows the resolved app localization",
    ),
]

# ---- key extraction -------------------------------------------------------

_LITERAL = r'"((?:[^"\\]|\\.)*)"'
_KEY_PATTERNS = [
    re.compile(r"String\(\s*localized:\s*" + _LITERAL),
    re.compile(
        r"\b(?:Text|Button|Picker|Toggle|Section|Label|TextField|"
        r"SecureField|Menu|ControlGroup|DisclosureGroup|"
        r"LabeledContent|Tab)\(\s*" + _LITERAL
    ),
    re.compile(r"\.navigationTitle\(\s*" + _LITERAL),
    re.compile(r"\.searchable\(\s*prompt:\s*" + _LITERAL),
    re.compile(r"\.confirmationDialog\(\s*" + _LITERAL),
    re.compile(r"\.alert\(\s*" + _LITERAL),
    re.compile(r"\.help\(\s*" + _LITERAL),
]

_INTERP = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")
_FORMAT_SPEC = re.compile(
    r"%(?:\d+\$)?[-+#0 ]*(?:\d+|\*)?(?:\.\d+)?"
    r"(?:hh|ll|h|l|L|z|t|j|q)?[diuUfFeEgGaA@oxXcsp]"
)
_CATALOG_ENTRY = re.compile(
    r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;'
)


def normalize_pattern(key: str) -> str:
    """Collapse interpolation and format specifiers to ``*`` so source
    keys and catalog keys compare by shape."""
    key = _INTERP.sub("\x00", key)
    key = _FORMAT_SPEC.sub("\x00", key)
    return key


def swift_unescape(literal: str) -> str:
    out, i = [], 0
    while i < len(literal):
        c = literal[i]
        if c == "\\" and i + 1 < len(literal):
            n = literal[i + 1]
            if n == "n":
                out.append("\n")
                i += 2
            elif n == "t":
                out.append("\t")
                i += 2
            elif n == '"':
                out.append('"')
                i += 2
            elif n == "\\":
                out.append("\\")
                i += 2
            elif n == "u" and i + 2 < len(literal) and literal[i + 2] == "{":
                j = literal.index("}", i)
                out.append(chr(int(literal[i + 3 : j], 16)))
                i = j + 1
            else:
                out.append(c)
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def extract_keys(path: Path) -> list[tuple[str, int]]:
    """Return [(key, line)] localization literals found in one file."""
    try:
        src = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return []
    found: list[tuple[str, int]] = []
    for pattern in _KEY_PATTERNS:
        for m in pattern.finditer(src):
            line = src.count("\n", 0, m.start(1)) + 1
            found.append((m.group(1), line))
    return found


def parse_catalog(path: Path) -> tuple[dict[str, tuple[str, int]], list[str]]:
    """Parse a .strings file -> ({key: (value, line)}, [problems])."""
    entries: dict[str, tuple[str, int]] = {}
    problems: list[str] = []
    in_block = False
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if in_block:
            if "*/" in line:
                in_block = False
            continue
        if line.startswith("/*"):
            if "*/" not in line:
                in_block = True
            continue
        if not line or line.startswith("//"):
            continue
        m = _CATALOG_ENTRY.match(line)
        if not m:
            problems.append(f"{path.name}:{lineno}: malformed line: {raw[:80]}")
            continue
        key, value = m.group(1), m.group(2)
        if key in entries:
            problems.append(
                f"{path.name}:{lineno}: duplicate key {key[:60]!r} "
                f"(first defined line {entries[key][1]})"
            )
        else:
            entries[key] = (value, lineno)
        # specifier parity: the ja value must take the same number of
        # arguments as the key template
        if len(_FORMAT_SPEC.findall(key)) != len(
            _FORMAT_SPEC.findall(value)
        ):
            problems.append(
                f"{path.name}:{lineno}: specifier count mismatch for "
                f"{key[:60]!r}"
            )
    return entries, problems


def audit() -> list[str]:
    problems: list[str] = []
    catalog_entries, catalog_problems = parse_catalog(CATALOG_PATH)
    problems.extend(catalog_problems)

    normalized_catalog: dict[str, str] = {}
    for key in catalog_entries:
        normalized_catalog.setdefault(normalize_pattern(key), key)

    source_files: list[Path] = []
    for root in SCAN_ROOTS:
        source_files.extend(sorted(root.rglob("*.swift")))

    seen: dict[str, tuple[str, int]] = {}
    for path in source_files:
        try:
            src = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        rel = path.relative_to(REPO_ROOT)
        for pattern, message in FORBIDDEN:
            for m in pattern.finditer(src):
                line = src.count("\n", 0, m.start()) + 1
                problems.append(f"{rel}:{line}: {message}")
        for key, line in extract_keys(path):
            seen.setdefault(key, (str(rel), line))

    for key, (rel, line) in sorted(seen.items()):
        decoded = swift_unescape(key)
        # the catalog stores keys in escaped source form; match either
        if key in catalog_entries or decoded in catalog_entries:
            continue
        if "\\(" in decoded:
            # interpolated literal -> pattern key in the catalog
            if normalize_pattern(decoded) in normalized_catalog:
                continue
        problems.append(
            f"{rel}:{line}: missing ja.lproj entry for {decoded[:70]!r}"
        )
    return problems


def main() -> int:
    problems = audit()
    for problem in problems:
        print(problem)
    if problems:
        print(f"\nlocalization audit: {len(problems)} problem(s)")
        return 1
    print("localization audit: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
