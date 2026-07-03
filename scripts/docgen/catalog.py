#!/usr/bin/env python3
"""
catalog.py — Extract service-catalog.json from fleet-infra manifests and env files.

Derivable facts only: chart, version, namespace, dependsOn, downstream,
layer, type, per-env config values. No prose or operational knowledge.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from lib.parse import get_nested, load_yaml_documents, load_yaml_documents_with_source

# ---------------------------------------------------------------------------
# Paths (relative to repo root)
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SERVICES_KUSTOMIZATION = REPO_ROOT / "base" / "services" / "kustomization.yaml"
BASE_ENV = REPO_ROOT / "base" / "services" / "environment.env"
DEV_ENV = REPO_ROOT / "clusters" / "stages" / "dev" / "clusters" / "services-amer" / "environment.env"
PROD_ENV = REPO_ROOT / "clusters" / "stages" / "prod" / "clusters" / "services-amer" / "environment.env"
SERVICES_DIR = REPO_ROOT / "base" / "services"
APPS_BASE_DIR = REPO_ROOT / "apps" / "base"
OUTPUT_FILE = REPO_ROOT / "service-catalog.json"

# ---------------------------------------------------------------------------
# Explicit env-var prefix mapping per service slug
# Services not listed here get no per-env config rows.
# ---------------------------------------------------------------------------
SERVICE_ENV_PREFIXES: dict[str, list[str]] = {
    "cilium":                    ["CILIUM_"],
    "traefik":                   ["TRAEFIK_"],
    "traefik-config":            [],
    "localstack":                ["LOCALSTACK_"],
    "cnpg-operator":             ["CNPG_OPERATOR_"],
    "scylla-operator":           ["SCYLLA_OPERATOR_"],
    "external-secrets-operator": ["EXTERNAL_SECRETS_"],
    "external-secrets-config":   [],
    "metrics-server":            ["METRICS_SERVER_"],
    "kube-prometheus-stack":     ["PROMETHEUS_", "GRAFANA_", "ALERTMANAGER_"],
    "weave-gitops":              ["WEAVE_GITOPS_"],
    "argocd":                    ["ARGOCD_"],
    "grafana-sa-setup":          [],
    "grafana-operator":          [],
    "grafana-config":            [],
    "grafana-dashboards":        [],
    "node-image-gc":             [],
    "keda":                      ["KEDA_"],
    "loki":                      ["LOKI_"],
    "promtail":                  ["PROMTAIL_"],
    "jaeger":                    ["JAEGER_"],
    "opentelemetry-collector":   ["OTEL_COLLECTOR_"],
    "postgresql-cluster":        ["POSTGRESQL_"],
    "redis-sentinel":            ["REDIS_"],
    "scylla-cluster":            ["SCYLLA_"],
    "scylla-manager":            ["SCYLLA_MANAGER_"],
    "n8n":                       ["N8N_"],
    "temporal":                  ["TEMPORAL_"],
    "ollama":                    ["OLLAMA_"],
    "code-tools":                ["CODE_TOOLS_"],
    "kagent":                    ["KAGENT_"],
    "agentgateway":              ["AGENTGATEWAY_"],
    "agentgateway-config":       [],
    "gateway-api-crds":          [],
    "kubescape":                 ["KUBESCAPE_", "KUBEVULN_"],
    "opencost":                  ["OPENCOST_"],
    "pgadmin4":                  ["PGADMIN4_"],
    "redisinsight":              ["REDISINSIGHT_"],
    # crossplane family (disabled, included for completeness)
    "crossplane":                ["CROSSPLANE_"],
    "crossplane-providers":      ["CROSSPLANE_AWS_PROVIDER_"],
    "crossplane-config":         [],
}

# ---------------------------------------------------------------------------
# Human-friendly display names
# ---------------------------------------------------------------------------
DISPLAY_NAMES: dict[str, str] = {
    "cilium":                    "Cilium",
    "traefik":                   "Traefik",
    "traefik-config":            "Traefik Config",
    "localstack":                "LocalStack",
    "cnpg-operator":             "CNPG Operator",
    "scylla-operator":           "Scylla Operator",
    "external-secrets-operator": "External Secrets Operator",
    "external-secrets-config":   "External Secrets Config",
    "metrics-server":            "Metrics Server",
    "kube-prometheus-stack":     "Kube Prometheus Stack",
    "weave-gitops":              "Weave GitOps",
    "argocd":                    "Argo CD",
    "grafana-sa-setup":          "Grafana SA Setup",
    "grafana-operator":          "Grafana Operator",
    "grafana-config":            "Grafana Config",
    "grafana-dashboards":        "Grafana Dashboards",
    "node-image-gc":             "Node Image GC",
    "keda":                      "KEDA",
    "loki":                      "Loki",
    "promtail":                  "Promtail",
    "jaeger":                    "Jaeger",
    "opentelemetry-collector":   "OpenTelemetry Collector",
    "postgresql-cluster":        "PostgreSQL Cluster",
    "redis-sentinel":            "Redis Sentinel",
    "scylla-cluster":            "ScyllaDB Cluster",
    "scylla-manager":            "Scylla Manager",
    "n8n":                       "N8N",
    "temporal":                  "Temporal",
    "ollama":                    "Ollama",
    "code-tools":                "Code Tools",
    "kagent":                    "kagent",
    "agentgateway":              "AgentGateway",
    "agentgateway-config":       "AgentGateway Config",
    "gateway-api-crds":          "Gateway API CRDs",
    "kubescape":                 "Kubescape",
    "opencost":                  "OpenCost",
    "pgadmin4":                  "pgAdmin4",
    "redisinsight":              "RedisInsight",
    "crossplane":                "Crossplane",
    "crossplane-providers":      "Crossplane Providers",
    "crossplane-config":         "Crossplane Config",
}

# ---------------------------------------------------------------------------
# Env-file parsing
# ---------------------------------------------------------------------------

def load_env_file(path: Path) -> dict[str, str]:
    """Parse a KEY=VALUE .env file, ignoring comments and blank lines."""
    env: dict[str, str] = {}
    if not path.exists():
        return env
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip().strip('"')
    return env


def merge_envs(*envs: dict[str, str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for e in envs:
        result.update(e)
    return result


def resolve_var(value: str, env: dict[str, str]) -> str:
    """Expand ${VAR} references using the given env dict."""
    def replacer(m: re.Match) -> str:
        original = m.group(0) or ""
        key = m.group(1)
        if key is None:
            return original
        return env.get(key, original)
    return re.sub(r"\$\{([^}]+)\}", replacer, value)


def filter_env_for_service(svc: str, env: dict[str, str]) -> dict[str, str]:
    prefixes = SERVICE_ENV_PREFIXES.get(svc, [])
    result: dict[str, str] = {}
    for k, v in env.items():
        if any(k.startswith(p) for p in prefixes):
            result[k] = v
    return result

# ---------------------------------------------------------------------------
# kustomization.yaml parsing
# ---------------------------------------------------------------------------

def parse_services_kustomization(path: Path) -> tuple[list[str], list[str], dict[str, str]]:
    """
    Returns:
        enabled:  list of enabled service slugs (in declaration order)
        disabled: list of disabled service slugs
        layers:   dict mapping slug → layer name
    """
    enabled: list[str] = []
    disabled: list[str] = []
    layers: dict[str, str] = {}
    current_layer = "Uncategorized"

    text = path.read_text()
    in_resources = False

    for line in text.splitlines():
        stripped = line.strip()

        if stripped.startswith("resources:"):
            in_resources = True
            continue

        if in_resources:
            # Stop at next top-level key (not indented)
            if stripped and not stripped.startswith("#") and not stripped.startswith("-") and ":" in stripped and not line.startswith(" "):
                in_resources = False
                continue

            # Detect layer comment lines (lines that are purely comments without a leading -)
            layer_match = re.match(r"^\s+#\s+(.+?)(?:\s*\(.*\))?\s*$", line)
            if layer_match and not re.search(r"^\s+#\s+-\s", line):
                comment_text = layer_match.group(1).strip()
                # Heuristic: treat it as a layer heading if it looks like one
                # (has capitalized words, not a parenthetical-only comment)
                if re.match(r"^[A-Z]", comment_text) and len(comment_text) < 80:
                    current_layer = comment_text
                continue

            # Disabled service: commented-out resource
            disabled_match = re.match(r"^\s+#\s+-\s+(\S+?)\.yaml\b", line)
            if disabled_match:
                slug = disabled_match.group(1)
                disabled.append(slug)
                layers[slug] = current_layer
                continue

            # Enabled service
            enabled_match = re.match(r"^\s+-\s+(\S+?)\.yaml\b", line)
            if enabled_match:
                slug = enabled_match.group(1)
                enabled.append(slug)
                layers[slug] = current_layer
                continue

    return enabled, disabled, layers

def _extract_depends_on(source: str) -> list[str]:
    """Extract dependsOn names from Flux Kustomization source text."""
    deps: list[str] = []
    in_depends = False
    for line in source.splitlines():
        if re.match(r"\s+dependsOn\s*:", line):
            in_depends = True
            continue
        if in_depends:
            m = re.match(r"\s+-\s+name\s*:\s*(\S+)", line)
            if m:
                deps.append(m.group(1))
            elif re.match(r"\s+\w+\s*:", line) and "name:" not in line:
                in_depends = False
    return deps


def _extract_health_checks(source: str) -> list[dict[str, str]]:
    """Extract healthChecks from Flux Kustomization source text."""
    checks: list[dict[str, str]] = []
    in_checks = False
    current: dict[str, str] = {}
    for line in source.splitlines():
        if re.match(r"\s+healthChecks\s*:", line):
            in_checks = True
            continue
        if in_checks:
            if re.match(r"\s+-\s+apiVersion\s*:", line):
                if current:
                    checks.append(current)
                current = {}
                m = re.match(r"\s+-\s+apiVersion\s*:\s*(\S+)", line)
                if m:
                    current["apiVersion"] = m.group(1)
            elif re.match(r"\s+kind\s*:\s*(\S+)", line):
                m = re.match(r"\s+kind\s*:\s*(\S+)", line)
                if m:
                    current["kind"] = m.group(1)
            elif re.match(r"\s+name\s*:\s*(\S+)", line):
                m = re.match(r"\s+name\s*:\s*(\S+)", line)
                if m:
                    current["name"] = m.group(1)
            elif re.match(r"\S", line):
                in_checks = False
    if current:
        checks.append(current)
    return checks


def _extract_timeout(source: str) -> str | None:
    """Extract spec.timeout scalar from source preserving inline comments."""
    in_spec = False
    spec_indent = 0
    for line in source.splitlines():
        spec_match = re.match(r"^(\s*)spec\s*:\s*$", line)
        if spec_match:
            in_spec = True
            spec_indent = len(spec_match.group(1))
            continue

        if in_spec:
            current_indent = len(line) - len(line.lstrip(" "))
            if line.strip() and current_indent <= spec_indent:
                in_spec = False
                continue

            timeout_match = re.match(r"^\s*timeout\s*:\s*(.*)$", line)
            if timeout_match:
                value = timeout_match.group(1).strip().strip('"').strip("'")
                return value or None
    return None


def parse_flux_kustomization(svc: str) -> dict[str, Any]:
    """Read base/services/<svc>.yaml and extract Flux Kustomization fields."""
    svc_yaml = SERVICES_DIR / f"{svc}.yaml"
    result: dict[str, Any] = {
        "path": f"apps/base/{svc}",
        "depends_on": [],
        "health_checks": [],
        "timeout": "5m",
        "source": f"apps/base/{svc}/",
    }
    if not svc_yaml.exists():
        return result

    text = svc_yaml.read_text()
    docs = load_yaml_documents_with_source(text)
    for source, doc in docs:
        kind = get_nested(doc, "kind")
        if kind == "Kustomization":
            path = get_nested(doc, "spec", "path")
            if path:
                result["path"] = path.lstrip("./")
                result["source"] = path.lstrip("./") + "/"
            timeout = _extract_timeout(source)
            if timeout:
                result["timeout"] = timeout
            result["depends_on"] = _extract_depends_on(source)
            result["health_checks"] = _extract_health_checks(source)
            break
    return result


def find_helmrelease_in_dir(app_dir: Path, env: dict[str, str]) -> dict[str, Any]:
    """
    Walk app_dir looking for a HelmRelease resource.
    Returns chart metadata dict or empty dict if none found.
    """
    if not app_dir.exists():
        return {}

    # Check direct helmrelease.yaml first, then any .yaml file
    candidates = [app_dir / "helmrelease.yaml"]
    candidates += [f for f in app_dir.glob("*.yaml") if f.name != "helmrelease.yaml"]

    for path in candidates:
        if not path.is_file():
            continue
        text = path.read_text()
        docs = load_yaml_documents_with_source(text)
        for _, doc in docs:
            kind = get_nested(doc, "kind")
            if kind != "HelmRelease":
                continue
            chart_name = get_nested(doc, "spec", "chart", "spec", "chart")
            chart_ver = get_nested(doc, "spec", "chart", "spec", "version")
            target_ns = (
                get_nested(doc, "spec", "targetNamespace")
                or get_nested(doc, "spec", "chart", "spec", "sourceRef", "namespace")
            )
            # Get namespace from metadata
            meta_ns = get_nested(doc, "metadata", "namespace")
            # Resolve version vars
            if chart_ver:
                chart_ver = resolve_var(chart_ver, env)
            # Find repo URL from the companion HelmRepository in the same file
            repo_url = None
            for _, d2 in docs:
                if get_nested(d2, "kind") == "HelmRepository":
                    repo_url = get_nested(d2, "spec", "url")
                    break
            return {
                "type": "HelmRelease",
                "chart": chart_name,
                "chart_version": chart_ver,
                "namespace": target_ns or meta_ns,
                "repo_url": repo_url,
            }
    return {}


def detect_app_type(app_dir: Path) -> str:
    """Detect the primary workload type in apps/base/<svc>/."""
    if not app_dir.exists():
        return "Kustomization"
    for fname in app_dir.glob("*.yaml"):
        text = fname.read_text()
        for doc in load_yaml_documents(text):
            kind = get_nested(doc, "kind")
            if kind in {"HelmRelease", "Deployment", "StatefulSet", "DaemonSet", "CronJob", "Job"}:
                return kind
    return "Kustomization"


def get_namespace_from_app(app_dir: Path) -> str | None:
    """Read namespace from namespace.yaml or first workload resource."""
    ns_file = app_dir / "namespace.yaml"
    if ns_file.exists():
        text = ns_file.read_text()
        for doc in load_yaml_documents(text):
            if get_nested(doc, "kind") == "Namespace":
                return get_nested(doc, "metadata", "name")
    return None

# ---------------------------------------------------------------------------
# Service catalog assembly
# ---------------------------------------------------------------------------

def build_catalog() -> dict[str, Any]:
    base_env = load_env_file(BASE_ENV)
    dev_env = merge_envs(base_env, load_env_file(DEV_ENV))
    prod_env = merge_envs(base_env, load_env_file(PROD_ENV))

    enabled, disabled, layers = parse_services_kustomization(SERVICES_KUSTOMIZATION)

    all_slugs = enabled + disabled
    catalog: dict[str, Any] = {}

    for svc in all_slugs:
        flux_info = parse_flux_kustomization(svc)
        app_dir = REPO_ROOT / flux_info["path"]

        helm_info = find_helmrelease_in_dir(app_dir, base_env)
        if not helm_info:
            svc_type = detect_app_type(app_dir)
        else:
            svc_type = "HelmRelease"

        namespace = (
            helm_info.get("namespace")
            or get_namespace_from_app(app_dir)
            or svc
        )

        display_name = DISPLAY_NAMES.get(svc) or " ".join(w.capitalize() for w in svc.replace("-", "_").split("_"))

        catalog[svc] = {
            "name": display_name,
            "slug": svc,
            "namespace": namespace,
            "layer": layers.get(svc, "Uncategorized"),
            "type": svc_type,
            "chart": helm_info.get("chart"),
            "chart_version": helm_info.get("chart_version"),
            "repo_url": helm_info.get("repo_url"),
            "depends_on": flux_info["depends_on"],
            "downstream": [],  # filled in reverse-index pass below
            "timeout": flux_info["timeout"],
            "health_checks": flux_info["health_checks"],
            "source": flux_info["source"],
            "enabled": svc in enabled,
            "dev":  filter_env_for_service(svc, dev_env),
            "prod": filter_env_for_service(svc, prod_env),
        }

    # Build reverse dependency (downstream) index
    for svc, entry in catalog.items():
        for dep in entry["depends_on"]:
            if dep in catalog:
                catalog[dep]["downstream"].append(svc)

    return catalog


def compute_catalog_sha(catalog: dict[str, Any]) -> str:
    serialized = json.dumps(catalog, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(serialized.encode()).hexdigest()[:16]


def main() -> None:
    print("Building service catalog...", file=sys.stderr)
    catalog = build_catalog()

    sha = compute_catalog_sha(catalog)
    output = {"_meta": {"catalog_sha": sha}, "services": catalog}

    OUTPUT_FILE.write_text(json.dumps(output, indent=2) + "\n")
    print(f"Wrote {len(catalog)} services to {OUTPUT_FILE}", file=sys.stderr)
    print(f"catalog_sha: {sha}", file=sys.stderr)

    enabled = sum(1 for s in catalog.values() if s["enabled"])
    disabled = sum(1 for s in catalog.values() if not s["enabled"])
    print(f"  {enabled} enabled, {disabled} disabled", file=sys.stderr)


if __name__ == "__main__":
    main()
