#!/usr/bin/env bash
# Pre-commit hook: validate all service-insights/*.yaml files against schema.
set -euo pipefail

VENV="scripts/docgen/.venv/bin/python3"

if ! command -v "$VENV" &>/dev/null; then
    echo "WARNING: docgen venv missing — skipping insight schema check. Run: make docs-setup"
    exit 0
fi

"$VENV" scripts/docgen/insight_schema.py
