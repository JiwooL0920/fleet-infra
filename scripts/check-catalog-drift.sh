#!/usr/bin/env bash
# Pre-push hook: auto-regenerate service-catalog.json if stale, then amend the commit.
set -euo pipefail

VENV="scripts/docgen/.venv/bin/python3"

if ! command -v "$VENV" &>/dev/null; then
    echo "WARNING: docgen venv missing — skipping catalog drift check. Run: make docs-setup"
    exit 0
fi

"$VENV" scripts/docgen/catalog.py >/dev/null 2>&1

if ! git diff --exit-code service-catalog.json >/dev/null 2>&1; then
    echo "service-catalog.json was stale — auto-updating and amending last commit..."
    git add service-catalog.json
    git commit --amend --no-edit --no-verify
    echo "Done. Re-run git push."
    exit 1
fi
