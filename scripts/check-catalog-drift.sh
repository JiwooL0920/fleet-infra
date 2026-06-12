#!/usr/bin/env bash
# Pre-commit hook: verify service-catalog.json is not stale.
set -euo pipefail

VENV="scripts/docgen/.venv/bin/python3"

if ! command -v "$VENV" &>/dev/null; then
    echo "WARNING: docgen venv missing — skipping catalog drift check. Run: make docs-setup"
    exit 0
fi

"$VENV" scripts/docgen/catalog.py >/dev/null 2>&1

if ! git diff --exit-code service-catalog.json >/dev/null 2>&1; then
    echo ""
    echo "ERROR: service-catalog.json is stale."
    echo "Run: make catalog && git add service-catalog.json"
    exit 1
fi
