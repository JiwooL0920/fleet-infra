#!/usr/bin/env python3
"""
validate.py — Structural validation of rendered documentation pages.

Checks:
  - Required headings present (## Overview, ## Dependencies, ## Purpose, ## Configuration, ## Operations, ## Related)
  - No empty tables (table row with only pipes and dashes/spaces)
  - Every adr_ref mentioned in a page exists in docs/adr/
  - Mermaid code fences are balanced (even number of ```mermaid fences)
  - TODO count under warning threshold
  - No unclosed Jinja2 template vars ({{ or }}) — indicates rendering errors

Usage:
    python3 validate.py [<file.md> ...]    # validate specific files
    python3 validate.py                    # validate all docs-output/components/*.md

Exit code: 0 = clean, 1 = errors, 2 = warnings only (with --strict-warnings)
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_DOCS_DIR = REPO_ROOT / "docs-output"
ADR_DIR = REPO_ROOT / "docs" / "adr"

REQUIRED_HEADINGS = [
    "## Overview",
    "## Dependencies",
    "## Purpose",
    "## Configuration",
    "## Operations",
    "## Related",
]

TODO_WARN_THRESHOLD = 5
ADR_REF_RE = re.compile(r"ADR-(\d+)", re.IGNORECASE)
MERMAID_FENCE_RE = re.compile(r"^```mermaid", re.MULTILINE)
FENCE_CLOSE_RE = re.compile(r"^```\s*$", re.MULTILINE)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _existing_adrs() -> set[str]:
    adrs: set[str] = set()
    if not ADR_DIR.exists():
        return adrs
    for f in ADR_DIR.glob("*.md"):
        stem = f.stem
        m_num = stem.split("-")[0] if "-" in stem else stem
        try:
            num = int(m_num)
            adrs.add(f"ADR-{num:03d}")
        except ValueError:
            pass
    return adrs


class ValidationResult:
    def __init__(self, path: Path):
        self.path = path
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    @property
    def ok(self) -> bool:
        return not self.errors


# ---------------------------------------------------------------------------
# Validators
# ---------------------------------------------------------------------------

def check_required_headings(text: str, result: ValidationResult) -> None:
    for heading in REQUIRED_HEADINGS:
        # Match heading at start of line (may have trailing text)
        if not re.search(r"^" + re.escape(heading), text, re.MULTILINE):
            result.error(f"Missing required heading: '{heading}'")


def check_empty_tables(text: str, result: ValidationResult) -> None:
    """Flag tables whose data rows contain only separators or are absent."""
    lines = text.splitlines()
    in_table = False
    header_seen = False
    separator_seen = False
    data_rows = 0
    table_start_line = 0

    for i, line in enumerate(lines):
        stripped = line.strip()
        is_table_row = stripped.startswith("|") and stripped.endswith("|")

        if is_table_row:
            if not in_table:
                in_table = True
                header_seen = False
                separator_seen = False
                data_rows = 0
                table_start_line = i + 1
                header_seen = True
            elif header_seen and not separator_seen:
                # Check if this is a separator row (|---|---|)
                inner = stripped.strip("|").strip()
                if re.match(r"^[-|: ]+$", inner):
                    separator_seen = True
                else:
                    data_rows += 1
            else:
                data_rows += 1
        else:
            if in_table:
                if separator_seen and data_rows == 0:
                    result.error(f"Line {table_start_line}: empty table (header + separator but no data rows)")
                in_table = False
                header_seen = False
                separator_seen = False
                data_rows = 0

    if in_table and separator_seen and data_rows == 0:
        result.error(f"Line {table_start_line}: empty table (header + separator but no data rows)")


def check_adr_refs(text: str, result: ValidationResult, existing_adrs: set[str]) -> None:
    """Ensure every ADR-NNN reference in the page exists in docs/adr/."""
    if not existing_adrs:
        return
    for m in ADR_REF_RE.finditer(text):
        ref = f"ADR-{int(m.group(1)):03d}"
        if ref not in existing_adrs:
            result.error(f"ADR reference '{ref}' not found in docs/adr/")


def check_mermaid_balance(text: str, result: ValidationResult) -> None:
    """Mermaid fences come in pairs: ```mermaid ... ```."""
    open_fences = len(MERMAID_FENCE_RE.findall(text))
    # Count matching closing ``` after each ```mermaid
    # Simple approach: count all ``` occurrences and ensure mermaid openers are <= total/2
    all_fences = text.count("```")
    if open_fences > 0 and all_fences % 2 != 0:
        result.error(f"Unbalanced code fences: {all_fences} total ``` occurrences (should be even)")


def check_todo_count(text: str, result: ValidationResult) -> None:
    todos = len(re.findall(r"<!--\s*TODO:", text))
    if todos > TODO_WARN_THRESHOLD:
        result.warn(f"{todos} TODO placeholders (threshold: {TODO_WARN_THRESHOLD})")
    elif todos > 0:
        result.warn(f"{todos} TODO placeholder(s) remain")


def check_rendering_artifacts(text: str, result: ValidationResult) -> None:
    """Detect unclosed Jinja2 template variables — indicates a rendering failure."""
    if "{{" in text and "}}" not in text:
        result.error("Unclosed Jinja2 template variable {{ found")
    # Check for raw Jinja2 blocks that weren't rendered
    if "{%" in text:
        result.error("Unrendered Jinja2 control tag {%...%} found in output")


def check_frontmatter(text: str, result: ValidationResult) -> None:
    """Page must have YAML frontmatter with catalog_sha and fleet_infra_commit."""
    if not text.startswith("---"):
        result.error("Missing frontmatter (page must start with ---)")
        return
    end = text.find("---", 3)
    if end == -1:
        result.error("Malformed frontmatter (no closing ---)")
        return
    front = text[3:end]
    if "catalog_sha:" not in front:
        result.error("Frontmatter missing 'catalog_sha'")
    if "fleet_infra_commit:" not in front:
        result.error("Frontmatter missing 'fleet_infra_commit'")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def validate_file(path: Path, existing_adrs: set[str]) -> ValidationResult:
    result = ValidationResult(path)
    try:
        text = path.read_text()
    except OSError as e:
        result.error(f"Cannot read file: {e}")
        return result

    check_frontmatter(text, result)
    # Only component pages (not index/architecture rollup pages) need all required headings
    if path.stem not in {"index", "architecture"}:
        check_required_headings(text, result)
    check_empty_tables(text, result)
    check_adr_refs(text, result, existing_adrs)
    check_mermaid_balance(text, result)
    check_todo_count(text, result)
    check_rendering_artifacts(text, result)

    return result


def validate_all(files: list[Path], strict_warnings: bool = False) -> int:
    existing_adrs = _existing_adrs()
    total_errors = 0
    total_warnings = 0

    for path in files:
        r = validate_file(path, existing_adrs)
        if r.errors or r.warnings:
            print(f"\n{path.name}:")
        for e in r.errors:
            print(f"  [ERROR] {e}")
        for w in r.warnings:
            print(f"  [WARN]  {w}")
        total_errors += len(r.errors)
        total_warnings += len(r.warnings)

    print()
    if total_errors:
        print(f"FAIL — {total_errors} error(s), {total_warnings} warning(s) across {len(files)} file(s)",
              file=sys.stderr)
        return 1
    if total_warnings:
        print(f"PASS with warnings — 0 errors, {total_warnings} warning(s) across {len(files)} file(s)",
              file=sys.stderr)
        return 2 if strict_warnings else 0
    print(f"OK — {len(files)} file(s) clean", file=sys.stderr)
    return 0


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Validate rendered flux-infra documentation pages")
    parser.add_argument("files", nargs="*", help="Markdown files to validate (default: docs-output/components/*.md)")
    parser.add_argument("--strict-warnings", action="store_true", help="Exit 2 on warnings")
    parser.add_argument("--docs-dir", default=str(DEFAULT_DOCS_DIR), help="Output dir to scan")
    args = parser.parse_args()

    if args.files:
        files = [Path(f) for f in args.files]
    else:
        docs_dir = Path(args.docs_dir)
        files = sorted((docs_dir / "components").glob("*.md"))
        if not files:
            print(f"No .md files found in {docs_dir}/components/", file=sys.stderr)
            sys.exit(0)

    sys.exit(validate_all(files, strict_warnings=args.strict_warnings))


if __name__ == "__main__":
    main()
