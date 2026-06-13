#!/usr/bin/env python3
"""
render.py — Deterministic documentation renderer.

Loads service-catalog.json + service-insights/<svc>.yaml files,
renders component pages and rollup pages via Jinja2 templates,
and writes them to an output directory.

Usage:
    python3 render.py [--output-dir <dir>] [--catalog <json>] [--services <slug,...>]

Defaults:
    --output-dir  docs-output/
    --catalog     service-catalog.json (repo root)
    --services    all enabled services
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import date
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. Run: pip install -r requirements.txt", file=sys.stderr)
    sys.exit(1)

try:
    from jinja2 import Environment, FileSystemLoader, StrictUndefined, TemplateNotFound
except ImportError:
    print("ERROR: jinja2 not installed. Run: pip install -r requirements.txt", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CATALOG_FILE = REPO_ROOT / "service-catalog.json"
INSIGHTS_DIR = REPO_ROOT / "service-insights"
TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"

GITHUB_BASE = "https://github.com/JiwooL0920/flux-infra"
BLOG_BASE = "https://jiwool0920.github.io/projects/flux-infra"

# Canonical layer ordering for display
LAYER_ORDER = [
    "Foundation services",
    "Foundation services (no dependencies",
    "Node maintenance",
    "Event-driven autoscaling",
    "Logging stack services",
    "Distributed tracing services",
    "Grafana Operator",
    "Database management services",
    "Database services",
    "Application services",
    "AI agent platform",
    "Security and cost observability",
    "Database UI services",
    # catch-alls
    "Infrastructure as Code services",
    "Uncategorized",
]

# ---------------------------------------------------------------------------
# Jinja2 environment setup
# ---------------------------------------------------------------------------

def make_jinja_env() -> Environment:
    env = Environment(
        loader=FileSystemLoader(str(TEMPLATES_DIR)),
        trim_blocks=True,
        lstrip_blocks=True,
    )
    # Custom filters
    env.filters["unique"] = lambda it: list(dict.fromkeys(it))
    env.filters["selectattr"] = _selectattr
    env.filters["rejectattr"] = _rejectattr
    env.filters["truncate"] = lambda s, n: s[:n] + "…" if len(s) > n else s
    return env


def _selectattr(iterable: Any, attr: str, val: Any = True) -> list:
    return [item for item in iterable if _getattr(item, attr) == val]


def _rejectattr(iterable: Any, attr: str, val: Any = True) -> list:
    return [item for item in iterable if _getattr(item, attr) != val]


def _getattr(item: Any, attr: str) -> Any:
    if isinstance(item, dict):
        return item.get(attr)
    return getattr(item, attr, None)

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

def load_catalog(path: Path) -> tuple[dict[str, Any], str]:
    """Return (services_dict, catalog_sha)."""
    data = json.loads(path.read_text())
    return data["services"], data["_meta"]["catalog_sha"]


def load_insight(svc_slug: str) -> dict[str, Any] | None:
    path = INSIGHTS_DIR / f"{svc_slug}.yaml"
    if not path.exists():
        return None
    text = path.read_text()
    data = yaml.safe_load(text)
    return data if isinstance(data, dict) else None


def get_fleet_commit() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, cwd=REPO_ROOT
        )
        return result.stdout.strip() or "unknown"
    except Exception:
        return "unknown"

# ---------------------------------------------------------------------------
# Layer helpers
# ---------------------------------------------------------------------------

def ordered_layers(services: dict[str, Any]) -> list[str]:
    """Return unique layer names in canonical display order."""
    seen_layers: list[str] = []
    for svc in services.values():
        layer = svc["layer"]
        if layer not in seen_layers:
            seen_layers.append(layer)
    # Sort by LAYER_ORDER index, unknowns go to end
    def sort_key(l: str) -> int:
        for i, prefix in enumerate(LAYER_ORDER):
            if l.startswith(prefix.rstrip("(")):
                return i
        return 999
    return sorted(seen_layers, key=sort_key)


def group_by_layer(services: dict[str, Any], layers: list[str]) -> dict[str, list]:
    result: dict[str, list] = {l: [] for l in layers}
    for svc in services.values():
        layer = svc["layer"]
        if layer not in result:
            result[layer] = []
        result[layer].append(svc)
    # Sort each layer's services alphabetically by name
    for layer in result:
        result[layer].sort(key=lambda s: s["name"])
    return result

# ---------------------------------------------------------------------------
# Mermaid graph generation
# ---------------------------------------------------------------------------

def build_mermaid_graph(services: dict[str, Any]) -> str:
    """Generate a flowchart TD mermaid graph from catalog dependencies."""
    lines = ["flowchart TD"]

    # Subgraph per layer
    seen_layers = ordered_layers(services)
    layer_svcs: dict[str, list] = group_by_layer(services, seen_layers)

    for layer in seen_layers:
        svcs = [s for s in layer_svcs[layer] if s["enabled"]]
        if not svcs:
            continue
        # Sanitize layer name for mermaid subgraph id
        layer_id = layer.replace(" ", "_").replace("(", "").replace(")", "").replace(",", "").replace("-", "_")
        lines.append(f'  subgraph {layer_id}["{layer}"]')
        for svc in svcs:
            node_id = svc["slug"].replace("-", "_")
            lines.append(f'    {node_id}["{svc["name"]}"]')
        lines.append("  end")

    # Edges
    for svc in services.values():
        if not svc["enabled"]:
            continue
        from_id = svc["slug"].replace("-", "_")
        for dep in svc["depends_on"]:
            if dep in services and services[dep]["enabled"]:
                to_id = dep.replace("-", "_")
                lines.append(f"  {to_id} --> {from_id}")

    return "\n".join(lines)

# ---------------------------------------------------------------------------
# Component page renderer
# ---------------------------------------------------------------------------

def render_component_page(
    svc: dict[str, Any],
    insight: dict[str, Any] | None,
    jinja_env: Environment,
    catalog_sha: str,
    fleet_commit: str,
) -> str:
    template = jinja_env.get_template("component-page.md.j2")
    return template.render(
        svc=svc,
        insight=insight,
        catalog_sha=catalog_sha,
        fleet_commit=fleet_commit,
        generated_at=date.today().isoformat(),
        github_base=GITHUB_BASE,
        blog_base=BLOG_BASE,
    )

# ---------------------------------------------------------------------------
# Rollup renderers
# ---------------------------------------------------------------------------

def render_rollup(
    template_name: str,
    jinja_env: Environment,
    services: dict[str, Any],
    catalog_sha: str,
    fleet_commit: str,
    **extra: Any,
) -> str:
    layers = ordered_layers(services)
    layer_services = group_by_layer(services, layers)
    mermaid_graph = build_mermaid_graph(services)

    template = jinja_env.get_template(template_name)
    return template.render(
        services=services,
        layers=layers,
        layer_services=layer_services,
        mermaid_graph=mermaid_graph,
        catalog_sha=catalog_sha,
        fleet_commit=fleet_commit,
        generated_at=date.today().isoformat(),
        github_base=GITHUB_BASE,
        blog_base=BLOG_BASE,
        **extra,
    )

# ---------------------------------------------------------------------------
# Nav YAML generator
# ---------------------------------------------------------------------------

def generate_nav_yaml(services: dict[str, Any]) -> str:
    """Generate mkdocs nav block for the flux-infra section."""
    layers = ordered_layers(services)
    layer_services = group_by_layer(services, layers)

    lines = ["- Flux Infra:"]
    lines.append("  - Overview: projects/flux-infra/index.md")
    lines.append("  - Architecture: projects/flux-infra/architecture.md")
    lines.append("  - Components:")
    lines.append("    - Index: projects/flux-infra/components/index.md")
    for layer in layers:
        svcs = [s for s in layer_services[layer] if s["enabled"]]
        if not svcs:
            continue
        lines.append(f"    - {layer}:")
        for svc in svcs:
            lines.append(f"      - {svc['name']}: projects/flux-infra/components/{svc['slug']}.md")
    return "\n".join(lines)

# ---------------------------------------------------------------------------
# Main render runner
# ---------------------------------------------------------------------------

def render_all(
    catalog_path: Path,
    output_dir: Path,
    service_filter: list[str] | None = None,
) -> dict[str, Path]:
    """
    Render all pages.
    Returns mapping of logical page key → output path.
    """
    services, catalog_sha = load_catalog(catalog_path)
    fleet_commit = get_fleet_commit()
    jinja_env = make_jinja_env()

    output_dir.mkdir(parents=True, exist_ok=True)
    components_dir = output_dir / "components"
    components_dir.mkdir(exist_ok=True)

    written: dict[str, Path] = {}

    # --- Component pages ---
    for slug, svc in services.items():
        if service_filter and slug not in service_filter:
            continue
        if not svc["enabled"] and not service_filter:
            continue  # skip disabled by default unless explicitly requested

        insight = load_insight(slug)
        if insight is None:
            print(f"  [WARN] No insight file for {slug} — rendering derivable sections + TODO placeholders", file=sys.stderr)

        content = render_component_page(svc, insight, jinja_env, catalog_sha, fleet_commit)
        out_path = components_dir / f"{slug}.md"
        out_path.write_text(content)
        written[f"components/{slug}"] = out_path

    # --- Rollup pages ---
    for template_name, out_name in [
        ("index.md.j2",            output_dir / "index.md"),
        ("architecture.md.j2",     output_dir / "architecture.md"),
        ("components-index.md.j2", components_dir / "index.md"),
    ]:
        content = render_rollup(template_name, jinja_env, services, catalog_sha, fleet_commit)
        out_name.write_text(content)
        written[out_name.stem] = out_name

    # --- Nav YAML ---
    nav_path = output_dir / "nav.yml"
    nav_path.write_text(generate_nav_yaml(services))
    written["nav"] = nav_path

    return written


def main() -> None:
    parser = argparse.ArgumentParser(description="Render flux-infra documentation pages")
    parser.add_argument("--output-dir", default=str(REPO_ROOT / "docs-output"), help="Output directory")
    parser.add_argument("--catalog", default=str(CATALOG_FILE), help="Path to service-catalog.json")
    parser.add_argument("--services", default="", help="Comma-separated service slugs to render (default: all enabled)")
    args = parser.parse_args()

    catalog_path = Path(args.catalog).resolve()
    output_dir = Path(args.output_dir).resolve()
    service_filter = [s.strip() for s in args.services.split(",") if s.strip()] or None

    if not catalog_path.exists():
        print(f"ERROR: catalog not found at {catalog_path}", file=sys.stderr)
        print("Run: make catalog", file=sys.stderr)
        sys.exit(1)

    print(f"Rendering to {output_dir} ...", file=sys.stderr)
    written = render_all(catalog_path, output_dir, service_filter)

    for key, path in sorted(written.items()):
        print(f"  {key}: {path}", file=sys.stderr)

    print(f"\nDone — {len(written)} files written to {output_dir}", file=sys.stderr)


if __name__ == "__main__":
    main()
