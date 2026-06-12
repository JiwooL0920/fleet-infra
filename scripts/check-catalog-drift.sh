#!/usr/bin/env bash
# Pre-commit hook: auto-regenerate service-catalog.json if stale.
# If the catalog was regenerated, it is staged automatically —
# just re-run git commit to include it.
set -euo pipefail

VENV="scripts/docgen/.venv/bin/python3"

if ! command -v "$VENV" &>/dev/null; then
    echo "WARNING: docgen venv missing — skipping catalog drift check. Run: make docs-setup"
    exit 0
fi

"$VENV" scripts/docgen/catalog.py >/dev/null 2>&1

if ! git diff --exit-code service-catalog.json >/dev/null 2>&1; then
    git add service-catalog.json
    echo "service-catalog.json was stale — auto-updated and staged. Re-run git commit."
    exit 1
fi
