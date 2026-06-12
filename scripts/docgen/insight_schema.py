#!/usr/bin/env python3
"""
insight_schema.py — Schema definition and validator for service-insights/<svc>.yaml files.

Each file holds the non-derivable engineering knowledge for one service:
prose, diagrams, troubleshooting, operational runbook content, ADR cross-refs, etc.
Derivable facts (chart, version, resources, dependsOn) come from service-catalog.json.

Run standalone:
    python3 insight_schema.py [<file.yaml> ...]        # validate specific files
    python3 insight_schema.py                          # validate all service-insights/*.yaml
"""

import sys
from pathlib import Path
from typing import Any
import re

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
INSIGHTS_DIR = REPO_ROOT / "service-insights"
ADR_DIR = REPO_ROOT / "docs" / "adr"

# ---------------------------------------------------------------------------
# Schema definition
# ---------------------------------------------------------------------------
#
# Each field below is defined as:
#   (required: bool, type: type | tuple[type, ...], description: str)
#
# Top-level optional fields:
SCHEMA: dict[str, tuple[bool, Any, str]] = {
    "intro":              (False, str, "Multi-paragraph markdown intro. Renders directly below the H1."),
    "purpose":            (False, str, "Why this service exists; what it does for the platform."),
    "purpose_rationale":  (False, str, "Optional: why this over a managed alternative."),
    "consumers":          (False, list, "List of consumer entries (see sub-schema below)."),
    "features":           (False, list, "List of {feature, detail} dicts."),
    "dependency_notes":   (False, dict, "Human nuance on upstream/downstream deps beyond what catalog has."),
    "architecture_diagrams": (False, list, "List of {title, mermaid} dicts."),
    "access":             (False, str, "Markdown: how to reach this service in-cluster and from a browser."),
    "operations":         (False, (list, dict), "List of {scenario, symptoms, steps, see_also} runbook entries (or legacy dict)."),
    "related":            (False, list, "List of {text, url} dicts."),
}

CONSUMER_SCHEMA: dict[str, tuple[bool, Any, str]] = {
    "name":        (True,  str, "Consuming service/component name."),
    "db":          (False, str, "Database/index used (for Redis etc.)."),
    "usage":       (False, str, "What the consumer does with this service."),
    "connection":  (False, str, "Connection string or method."),
    "notes":       (False, str, "Extra context."),
}

DEPENDENCY_NOTE_SCHEMA: dict[str, tuple[bool, Any, str]] = {
    # upstream/downstream are lists of {service, status/type/reason, notes?}
    "upstream":        (False, list, "Notes on upstream dependencies."),
    "downstream":      (False, list, "Notes on downstream dependents."),
    "upstream_note":   (False, str,  "Optional callout/note for the upstream section."),
    "downstream_note": (False, str,  "Optional callout/note for the downstream section."),
}

OPERATIONS_SCHEMA: dict[str, tuple[bool, Any, str]] = {
    "scenario":  (True,  str,  "Short title for the failure scenario."),
    "symptoms":  (False, str,  "What the operator observes — error messages, alert names."),
    "steps":     (False, list, "Ordered list of shell commands or checks."),
    "see_also":  (False, list, "List of ADR filenames relevant to this scenario."),
}

ARCHITECTURE_DIAGRAM_SCHEMA: dict[str, tuple[bool, Any, str]] = {
    "title":   (True, str, "Display title for the diagram."),
    "mermaid": (True, str, "Raw mermaid graph definition (no fences)."),
}

RELATED_SCHEMA: dict[str, tuple[bool, Any, str]] = {
    "text": (True, str, "Link text."),
    "url":  (True, str, "Absolute URL."),
}

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

class ValidationError:
    def __init__(self, path: str, message: str, level: str = "error"):
        self.path = path
        self.message = message
        self.level = level  # "error" | "warning"

    def __str__(self) -> str:
        icon = "ERROR" if self.level == "error" else "WARN"
        return f"[{icon}] {self.path}: {self.message}"


def _validate_dict_schema(
    data: dict,
    schema: dict[str, tuple[bool, Any, str]],
    path: str,
    errors: list[ValidationError],
) -> None:
    for field, (required, expected_type, _desc) in schema.items():
        if field not in data:
            if required:
                errors.append(ValidationError(path, f"required field '{field}' is missing"))
        else:
            val = data[field]
            if not isinstance(val, expected_type):
                type_name = " or ".join(t.__name__ for t in expected_type) if isinstance(expected_type, tuple) else expected_type.__name__
                errors.append(
                    ValidationError(path, f"'{field}' must be {type_name}, got {type(val).__name__}")
                )

    # Unknown fields → warning
    for field in data:
        if field not in schema:
            errors.append(ValidationError(f"{path}.{field}", "unknown field (typo?)", level="warning"))


def _collect_adr_refs(operations: list | None) -> list[str]:
    refs: list[str] = []
    if not operations:
        return refs
    for scenario in operations:
        if isinstance(scenario, dict):
            for ref in (scenario.get("see_also", []) or []):
                # Normalise full path "docs/adr/002-loki-redis.md" → "ADR-002"
                m = re.search(r'(\d+)', str(ref))
                if m:
                    refs.append(f"ADR-{int(m.group(1)):03d}")
                else:
                    refs.append(str(ref))
    return refs


def _existing_adrs() -> set[str]:
    adrs: set[str] = set()
    if not ADR_DIR.exists():
        return adrs
    for f in ADR_DIR.glob("*.md"):
        stem = f.stem  # e.g. "002-loki-redis-direct-connection"
        # Extract ADR ID in the form "ADR-NNN"
        m_num = stem.split("-")[0] if "-" in stem else stem
        try:
            num = int(m_num)
            adrs.add(f"ADR-{num:03d}")
        except ValueError:
            pass
    return adrs


def validate_insight_file(path: Path) -> list[ValidationError]:
    errors: list[ValidationError] = []
    prefix = path.name

    try:
        text = path.read_text()
        data = yaml.safe_load(text)
    except yaml.YAMLError as e:
        errors.append(ValidationError(prefix, f"YAML parse error: {e}"))
        return errors

    if data is None:
        # Empty file is allowed (stub)
        return errors

    if not isinstance(data, dict):
        errors.append(ValidationError(prefix, "top-level must be a YAML mapping"))
        return errors

    _validate_dict_schema(data, SCHEMA, prefix, errors)

    # --- consumers ---
    for i, consumer in enumerate(data.get("consumers", []) or []):
        if isinstance(consumer, dict):
            _validate_dict_schema(consumer, CONSUMER_SCHEMA, f"{prefix}.consumers[{i}]", errors)

    # --- features ---
    for i, feat in enumerate(data.get("features", []) or []):
        if isinstance(feat, dict):
            if "feature" not in feat:
                errors.append(ValidationError(f"{prefix}.features[{i}]", "must have 'feature' key"))
            if "detail" not in feat:
                errors.append(ValidationError(f"{prefix}.features[{i}]", "must have 'detail' key"))

    # --- dependency_notes ---
    dep_notes = data.get("dependency_notes")
    if dep_notes is not None:
        if isinstance(dep_notes, dict):
            _validate_dict_schema(dep_notes, DEPENDENCY_NOTE_SCHEMA, f"{prefix}.dependency_notes", errors)

    # --- architecture_diagrams ---
    for i, diag in enumerate(data.get("architecture_diagrams", []) or []):
        if isinstance(diag, dict):
            _validate_dict_schema(diag, ARCHITECTURE_DIAGRAM_SCHEMA, f"{prefix}.architecture_diagrams[{i}]", errors)
            mermaid = diag.get("mermaid", "")
            if mermaid:
                # Sanity-check: should not be wrapped in ``` fences
                if "```" in mermaid:
                    errors.append(ValidationError(
                        f"{prefix}.architecture_diagrams[{i}].mermaid",
                        "remove ``` fences — the renderer wraps it automatically",
                    ))

    # --- operations ---
    ops = data.get("operations")
    if ops is not None:
        if isinstance(ops, list):
            # New format: list of {scenario, symptoms, steps, see_also}
            for i, scenario in enumerate(ops):
                if isinstance(scenario, dict):
                    _validate_dict_schema(scenario, OPERATIONS_SCHEMA, f"{prefix}.operations[{i}]", errors)
                    steps = scenario.get("steps")
                    if steps is not None and not isinstance(steps, list):
                        errors.append(ValidationError(f"{prefix}.operations[{i}].steps", "must be a list of strings"))
        elif not isinstance(ops, dict):
            errors.append(ValidationError(f"{prefix}.operations", "must be a list of scenario objects or a legacy dict"))

    # --- ADR refs exist in docs/adr/ ---
    existing = _existing_adrs()
    if existing:  # skip check if ADR dir is empty/missing
        for ref in _collect_adr_refs(ops):
            if ref not in existing:
                errors.append(
                    ValidationError(prefix, f"adr_ref '{ref}' not found in docs/adr/ (existing: {sorted(existing)})")
                )

    # --- related ---
    for i, rel in enumerate(data.get("related", []) or []):
        if isinstance(rel, dict):
            _validate_dict_schema(rel, RELATED_SCHEMA, f"{prefix}.related[{i}]", errors)
            url = rel.get("url", "")
            if url and not url.startswith(("http://", "https://")):
                errors.append(ValidationError(
                    f"{prefix}.related[{i}].url",
                    f"should be an absolute URL, got: {url!r}",
                ))

    return errors


def validate_all(files: list[Path]) -> int:
    """Validate all files, return exit code (0=ok, 1=errors)."""
    total_errors = 0
    total_warnings = 0

    for path in files:
        errs = validate_insight_file(path)
        hard = [e for e in errs if e.level == "error"]
        soft = [e for e in errs if e.level == "warning"]
        if errs:
            for e in errs:
                print(str(e))
        total_errors += len(hard)
        total_warnings += len(soft)

    if total_warnings:
        print(f"\n{total_warnings} warning(s)", file=sys.stderr)
    if total_errors:
        print(f"{total_errors} error(s) — fix before generating docs", file=sys.stderr)
        return 1
    print(f"OK — {len(files)} insight file(s) validated", file=sys.stderr)
    return 0


def main() -> None:
    if len(sys.argv) > 1:
        files = [Path(a) for a in sys.argv[1:]]
    else:
        files = sorted(INSIGHTS_DIR.glob("*.yaml"))

    if not files:
        print("No insight files found.", file=sys.stderr)
        sys.exit(0)

    sys.exit(validate_all(files))


if __name__ == "__main__":
    main()
