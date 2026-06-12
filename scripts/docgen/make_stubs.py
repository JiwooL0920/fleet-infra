#!/usr/bin/env python3
"""Generate minimal service-insights/<slug>.yaml stubs for services that don't have one yet."""

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CATALOG_FILE = REPO_ROOT / "service-catalog.json"
INSIGHTS_DIR = REPO_ROOT / "service-insights"

STUB_TEMPLATE = """\
# service-insights/{slug}.yaml
# Auto-generated stub. Fill in the sections below to enrich the rendered component page.
# Config values (chart version, resource limits, replica counts) come from service-catalog.json — do NOT copy them here.
# Reference: scripts/docgen/insight_schema.py for full schema.

intro: |
  <!-- TODO: Write a 1-2 paragraph intro explaining what {name} is and why it exists in this platform. -->

purpose: |
  <!-- TODO: Explain what {name} does for the platform and why it was chosen over alternatives. -->

# Uncomment and fill in as needed:
#
# purpose_rationale: |
#   Why {name} over a managed alternative.
#
# features:
#   - feature: Feature name
#     detail: What it does and why it matters.
#
# architecture_diagrams:
#   - title: Component diagram
#     mermaid: |
#       graph TD
#           A[{name}] --> B[...]
#
# access: |
#   How to reach this service in-cluster and from a browser.
#
# operations:
#   verification: |
#     ```bash
#     kubectl get pods -n {namespace}
#     ```
#   troubleshooting:
#     - symptom: Something is broken
#       cause: Why it breaks
#       resolution: How to fix it
#
# related:
#   - text: Official docs
#     url: https://...
"""


def main() -> None:
    catalog = json.loads(CATALOG_FILE.read_text())
    services = catalog["services"]

    created = 0
    skipped = 0
    for slug, svc in sorted(services.items()):
        if not svc["enabled"]:
            continue
        path = INSIGHTS_DIR / f"{slug}.yaml"
        if path.exists():
            skipped += 1
            continue
        stub = STUB_TEMPLATE.format(
            slug=slug,
            name=svc["name"],
            namespace=svc["namespace"],
        )
        path.write_text(stub)
        print(f"  Created: service-insights/{slug}.yaml")
        created += 1

    print(f"\n{created} stub(s) created, {skipped} already existed.", file=sys.stderr)


if __name__ == "__main__":
    main()
