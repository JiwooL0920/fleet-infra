#!/usr/bin/env python3
"""
insight_draft.py — Use opencode to draft prose fields of a service insight YAML.

Drafts ONLY the non-derivable prose fields:
  intro, purpose, purpose_rationale, features

Does NOT touch config values (those live in service-catalog.json).
Does NOT overwrite fields that are already filled.

The LLM is given:
  - The service's catalog entry (chart, version, deps, downstream, env vars)
  - All manifest files from apps/base/<svc>/
  - The Flux Kustomization (base/services/<svc>.yaml)
  - Any ADR files that mention the service
  - The redis-sentinel.yaml golden insight as a style contract
  - Explicit instructions not to invent config values

Usage:
    python3 insight_draft.py <slug>              # draft prose for one service
    python3 insight_draft.py traefik loki kagent # batch

Output is written directly to service-insights/<slug>.yaml.
Run 'make validate-insights' afterward to verify YAML is valid.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CATALOG_FILE = REPO_ROOT / "service-catalog.json"
INSIGHTS_DIR = REPO_ROOT / "service-insights"
ADR_DIR = REPO_ROOT / "docs" / "adr"
APPS_BASE = REPO_ROOT / "apps" / "base"
SERVICES_DIR = REPO_ROOT / "base" / "services"
GOLDEN_INSIGHT = INSIGHTS_DIR / "redis-sentinel.yaml"

MAX_MANIFEST_BYTES = 12_000   # cap per service to avoid token overload
MAX_ADR_BYTES = 4_000
OPENCODE_CMD = "opencode"

# Fields we draft; never touch fields outside this list
PROSE_FIELDS = ["intro", "purpose", "purpose_rationale", "features", "architecture_diagrams", "operations"]

# ---------------------------------------------------------------------------
# Context builders
# ---------------------------------------------------------------------------

def load_catalog_entry(slug: str) -> dict:
    catalog = json.loads(CATALOG_FILE.read_text())
    svc = catalog["services"].get(slug)
    if not svc:
        print(f"ERROR: '{slug}' not found in service-catalog.json", file=sys.stderr)
        sys.exit(1)
    return svc


def collect_manifests(svc: dict) -> str:
    source_path = svc.get("source", "").rstrip("/")
    app_dir = REPO_ROOT / source_path
    flux_yaml = SERVICES_DIR / f"{svc['slug']}.yaml"

    parts = []

    # Flux Kustomization
    if flux_yaml.exists():
        parts.append(f"# base/services/{svc['slug']}.yaml (Flux Kustomization — dependsOn, timeout)\n")
        parts.append(flux_yaml.read_text())

    # All manifest files in apps/base/<svc>/
    if app_dir.exists():
        for f in sorted(app_dir.rglob("*.yaml")):
            try:
                text = f.read_text()
                rel = f.relative_to(REPO_ROOT)
                parts.append(f"\n# {rel}\n")
                parts.append(text)
            except Exception:
                pass

    combined = "\n".join(parts)
    if len(combined) > MAX_MANIFEST_BYTES:
        combined = combined[:MAX_MANIFEST_BYTES] + "\n... (truncated)"
    return combined


def find_relevant_adrs(slug: str, svc_name: str) -> str:
    if not ADR_DIR.exists():
        return ""
    parts = []
    search_terms = {slug, svc_name, slug.replace("-", " ")}
    for adr_file in sorted(ADR_DIR.glob("*.md")):
        text = adr_file.read_text()
        if any(term.lower() in text.lower() for term in search_terms):
            rel = adr_file.relative_to(REPO_ROOT)
            parts.append(f"\n# {rel}\n{text[:MAX_ADR_BYTES]}")
    return "\n".join(parts) if parts else ""


def catalog_summary(svc: dict) -> str:
    lines = [
        f"Service slug:    {svc['slug']}",
        f"Display name:    {svc['name']}",
        f"Namespace:       {svc['namespace']}",
        f"Layer:           {svc['layer']}",
        f"Type:            {svc['type']}",
    ]
    if svc.get("chart"):
        lines.append(f"Helm chart:      {svc['chart']} v{svc.get('chart_version', '?')}")
    if svc.get("repo_url"):
        lines.append(f"Chart registry:  {svc['repo_url']}")
    if svc.get("depends_on"):
        lines.append(f"Depends on:      {', '.join(svc['depends_on'])}")
    if svc.get("downstream"):
        lines.append(f"Downstream:      {', '.join(svc['downstream'])}")

    dev = svc.get("dev", {})
    prod = svc.get("prod", {})
    if dev or prod:
        lines.append("\nKey env vars (dev / prod):")
        all_keys = sorted(set(list(dev.keys()) + list(prod.keys())))
        for k in all_keys[:20]:   # cap to avoid token overload
            lines.append(f"  {k}: {dev.get(k, '—')} / {prod.get(k, '—')}")
    return "\n".join(lines)

# ---------------------------------------------------------------------------
# Prompt builder
# ---------------------------------------------------------------------------


SYSTEM_PROMPT = """You are filling in the prose sections of a service insight YAML file for a GitOps Kubernetes homelab.

Draft ONLY these YAML fields:
  - intro         (multi-paragraph markdown — what is this technology, what makes it distinctive)
  - purpose       (why this specific service runs in THIS platform — its concrete role here)
  - purpose_rationale  (optional — why THIS tech over alternatives; omit key entirely if not interesting)
  - features      (list of {feature, detail} pairs — key capabilities actually configured in the manifests)
  - architecture_diagrams  (list of {title, mermaid} pairs — topology and/or flow diagrams)
  - operations  (list of {scenario, symptoms, steps, see_also} — failure modes and runbooks)

Hard constraints — prose:
- Output ONLY a valid YAML document. No preamble, no explanation, no markdown code fence.
- Start the output with the key `intro:`. Nothing before it.
- Do NOT hardcode config values (CPU, memory, replica counts, chart versions) — those come from service-catalog.json.
- Do NOT fabricate troubleshooting steps, consumer lists, or ADR references — those are out of scope.
- The `features` list must reflect features ACTUALLY CONFIGURED in the manifests, not generic product marketing.
- Keep `intro` factual and technical — 2-4 paragraphs, written as a senior SRE who designed this platform.
- Keep `purpose` concrete — explain the specific workload this serves, not the generic product use case.
- CRITICAL: Every `detail` value under `features` MUST use a block scalar (`detail: |`), never a plain
  scalar. Plain scalars break YAML parsing when they contain backtick code like `key: value`. No exceptions.

Hard constraints — operations:
- Write 3-6 scenarios covering the most common real-world failure modes for this technology.
- `scenario` is a short title (e.g. "Master failover not completing", "Pod CrashLoopBackOff on startup").
- `symptoms` is what an operator would observe first — error messages, kubectl output, alert names.
- `steps` are ordered shell commands or checks using the EXACT resource names visible in the manifests
  (correct namespace, service name, secret name, configmap name). Never use placeholder names like
  `<your-namespace>` — use the real values from the manifests provided.
- Commands must be executable as-is on a Kind cluster with kubectl access.
- Include `see_also` only for ADR files that are actually relevant (shown in context); omit the field
  if no ADR applies to this scenario.
- Write at SRE level — skip trivial steps like "check if pod is running". Start from the point where
  basic health checks have failed and deeper investigation is needed.


- Every node and edge MUST be traceable to the manifests, env vars, catalog dependsOn, or downstream list.
  No inferred connections. If you cannot source an edge from the provided context, omit it.
- The `mermaid` value is the raw Mermaid definition — NO fences (no triple backticks), NO language tag.
- Prefer `graph TD` for deployment topology (pods, volumes, sidecars, config sources, service ports).
- Add a second diagram only if there is a meaningful dynamic flow to show (e.g. failover sequence,
  request routing, auth handshake). Use `sequenceDiagram` for temporal flows.
- Label edges with the actual port, protocol, or relationship visible in the manifests.
- Use subgraphs to group components in the same namespace.
- Omit diagrams entirely (omit the `architecture_diagrams` key) if the service has fewer than
  3 interesting internal components — a single-pod service with no meaningful topology is not worth diagramming.

Output format:
intro: |
  <markdown paragraphs>

purpose: |
  <markdown paragraphs>

purpose_rationale: |
  <markdown paragraphs — omit this key entirely if the choice is obvious>

features:
  - feature: <name>
    detail: |
      <one sentence — MUST use block scalar (|) so that backtick code like `key: value` is safe>

architecture_diagrams:
  - title: <diagram title>
    mermaid: |
      graph TD
          <nodes and edges — no fences>
  - title: <optional second diagram>
    mermaid: |
      sequenceDiagram
          <sequence — no fences>

operations:
  - scenario: <failure scenario title>
    symptoms: |
      <what the operator observes — error messages, alert names, kubectl output>
    steps:
      - <exact shell command or check using real resource names from the manifests>
      - <next step>
    see_also:
      - <ADR filename e.g. docs/adr/002-loki-redis-direct-connection.md — omit if none>
  - scenario: <next scenario>
    ...
"""

# ---------------------------------------------------------------------------
# LLM invocation
# ---------------------------------------------------------------------------

def run_opencode(prompt_file: Path, context_files: list[Path]) -> str:
    """Call opencode run and return stdout.

    Strategy: attach the full context as a file (-f), pass SYSTEM_PROMPT as the message
    so opencode's message arg is a short, well-formed instruction rather than a file path.
    """
    # opencode run takes message as positional text args
    # -f attaches files as context the LLM can read
    cmd = [
        OPENCODE_CMD, "run",
        SYSTEM_PROMPT,
        "--dangerously-skip-permissions",
        "-f", str(prompt_file),   # context: catalog + manifests + ADRs + golden example
    ]
    for f in context_files:
        cmd += ["-f", str(f)]

    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )
    if result.returncode != 0:
        print(f"opencode stderr:\n{result.stderr[:2000]}", file=sys.stderr)
        raise RuntimeError(f"opencode exited with code {result.returncode}")
    return result.stdout


def _sanitize_plain_scalars(text: str) -> str:
    """
    Convert plain scalar YAML values that contain ': ' into block scalars.

    In YAML 1.1 (used by PyYAML), ': ' inside an unquoted plain scalar is a parse
    error — it looks like a nested mapping indicator. This commonly occurs when the
    LLM embeds backtick code snippets like `key: value` in a `detail:` line.

    Example — bad (plain scalar, YAML parse error):
        detail: Configured with `db.type: postgresdb` instead of SQLite

    After sanitization — good (block scalar):
        detail: |
          Configured with `db.type: postgresdb` instead of SQLite
    """
    result = []
    for line in text.splitlines():
        # Match: <whitespace><word-key>: <plain-scalar-value>
        # Plain scalar: doesn't start with |, >, ', ", -, [, {
        m = re.match(r'^(\s+)([\w-]+):\s+([^|>\'"\[{].*)$', line)
        if m:
            indent, key, value = m.group(1), m.group(2), m.group(3)
            # Only intervene if the value contains ': ' (the problematic pattern)
            if ': ' in value:
                result.append(f"{indent}{key}: |")
                result.append(f"{indent}  {value}")
                continue
        result.append(line)
    return "\n".join(result)


def extract_yaml_from_output(raw: str) -> str:
    """
    Strip any preamble/postamble from LLM output, then sanitize plain scalars
    that would cause PyYAML to fail on ': ' sequences.
    Accepts either raw YAML or YAML wrapped in a ```yaml ... ``` fence.
    """
    # Try to extract from a yaml code fence first
    fence_match = re.search(r"```(?:yaml)?\n(.*?)```", raw, re.DOTALL)
    if fence_match:
        yaml_text = fence_match.group(1).strip()
    else:
        # Otherwise strip everything before the first YAML key
        lines = raw.splitlines()
        start = 0
        for i, line in enumerate(lines):
            if re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*\s*:", line):
                start = i
                break
        yaml_text = "\n".join(lines[start:]).strip()

    return _sanitize_plain_scalars(yaml_text)

# ---------------------------------------------------------------------------
# Insight YAML merging
# ---------------------------------------------------------------------------

def is_stub_value(value) -> bool:
    """Return True if a field value looks like an unfilled stub."""
    if value is None:
        return True
    # An empty list is a stub
    if isinstance(value, list) and len(value) == 0:
        return True
    s = str(value).strip()
    if not s:
        return True
    # HTML comment-only values (e.g. "<!-- TODO: ... -->")
    cleaned = re.sub(r"<!--.*?-->", "", s, flags=re.DOTALL).strip()
    return not cleaned


def merge_into_stub(
    stub_path: Path,
    drafted: dict,
    force: bool = False,
    only_fields: list[str] | None = None,
) -> None:
    """
    Load existing stub YAML, overwrite prose fields according to these rules:
      - If `only_fields` is set, restrict to those fields only.
      - If `force` is True, overwrite even already-filled fields.
      - Otherwise, only overwrite fields that are empty / TODO placeholders.
    """
    existing_text = stub_path.read_text()
    existing = yaml.safe_load(existing_text) or {}

    target_fields = only_fields if only_fields else PROSE_FIELDS

    changed = []
    for field in target_fields:
        if field not in drafted:
            continue
        new_val = drafted[field]
        if not new_val:
            continue
        old_val = existing.get(field)
        if force or is_stub_value(old_val):
            existing[field] = new_val
            changed.append(field)
        else:
            print(f"  Skipping '{field}' — already filled (use --force to overwrite)", file=sys.stderr)

    if not changed:
        print(f"  No fields updated (all already filled or LLM returned nothing useful)", file=sys.stderr)
        return

    # Write back — preserve field order: PROSE_FIELDS first, then the rest
    ordered = {}
    for f in PROSE_FIELDS:
        if f in existing:
            ordered[f] = existing[f]
    for f in existing:
        if f not in ordered:
            ordered[f] = existing[f]

    # Dump with block scalars preserved
    stub_path.write_text(
        yaml.dump(ordered, allow_unicode=True, default_flow_style=False, width=100, sort_keys=False)
    )
    print(f"  Updated fields: {', '.join(changed)}", file=sys.stderr)

# ---------------------------------------------------------------------------
# Per-service drafting
# ---------------------------------------------------------------------------

def draft_service(slug: str, force: bool = False, fields: list[str] | None = None) -> None:
    print(f"\n{'='*60}", file=sys.stderr)
    print(f"Drafting insight for: {slug}", file=sys.stderr)
    if force:
        print(f"  --force: overwriting existing content", file=sys.stderr)
    if fields:
        print(f"  --fields: {', '.join(fields)}", file=sys.stderr)

    stub_path = INSIGHTS_DIR / f"{slug}.yaml"
    if not stub_path.exists():
        print(f"  ERROR: stub not found at {stub_path}", file=sys.stderr)
        return

    svc = load_catalog_entry(slug)
    manifests = collect_manifests(svc)
    adrs = find_relevant_adrs(slug, svc["name"])
    golden = GOLDEN_INSIGHT.read_text() if GOLDEN_INSIGHT.exists() else ""

    # Build the context file (attached as -f; LLM reads it as context)
    context_parts = [
        "## Service catalog entry",
        "```",
        catalog_summary(svc),
        "```",
        "",
        "## Kubernetes manifests",
        "```yaml",
        manifests,
        "```",
    ]
    if adrs:
        context_parts += ["", "## Relevant ADRs", adrs]
    if golden:
        context_parts += [
            "",
            "## Style reference — match this depth and tone",
            "The following is the redis-sentinel insight YAML. Match this level of detail,"
            " specificity, and engineering depth. Note especially the architecture_diagrams"
            " — edges are labeled with real ports/protocols visible in the manifests:",
            "```yaml",
            golden[:4000],
            "```",
        ]

    context = "\n".join(context_parts)

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", prefix=f"insight-ctx-{slug}-", delete=False
    ) as f:
        f.write(context)
        context_file = Path(f.name)

    try:
        print(f"  Running opencode...", file=sys.stderr)
        raw_output = run_opencode(context_file, [])
        yaml_text = extract_yaml_from_output(raw_output)

        # Validate it parses as YAML
        try:
            drafted = yaml.safe_load(yaml_text)
        except yaml.YAMLError as e:
            print(f"  ERROR: LLM returned invalid YAML: {e}", file=sys.stderr)
            print(f"  Raw output snippet: {raw_output[:500]}", file=sys.stderr)
            return

        if not isinstance(drafted, dict):
            print(f"  ERROR: LLM output is not a YAML mapping", file=sys.stderr)
            return

        merge_into_stub(stub_path, drafted, force=force, only_fields=fields)

    finally:
        context_file.unlink(missing_ok=True)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(
        description="Draft prose fields of service-insights/<slug>.yaml using opencode."
    )
    parser.add_argument("slugs", nargs="+", metavar="slug", help="Service slug(s) to draft")
    parser.add_argument(
        "--force", "-f",
        action="store_true",
        help="Overwrite fields even if already filled (use after architecture refactor)",
    )
    parser.add_argument(
        "--fields",
        metavar="FIELD,...",
        help=(
            "Comma-separated subset of fields to re-draft "
            "(e.g. --fields architecture_diagrams,purpose). "
            f"Valid: {', '.join(PROSE_FIELDS)}"
        ),
    )
    args = parser.parse_args()

    only_fields = None
    if args.fields:
        only_fields = [f.strip() for f in args.fields.split(",")]
        invalid = [f for f in only_fields if f not in PROSE_FIELDS]
        if invalid:
            print(f"ERROR: unknown fields: {invalid}. Valid: {PROSE_FIELDS}", file=sys.stderr)
            sys.exit(1)

    for slug in args.slugs:
        draft_service(slug, force=args.force, fields=only_fields)

    print(f"\nDone. Run 'make validate-insights' to verify.", file=sys.stderr)


if __name__ == "__main__":
    main()
