#!/usr/bin/env bash
# Pre-commit: for staged changes under apps/base/<slug>/ or base/services/<slug>.yaml,
# ensure service-insights/<slug>.yaml exists (stub), optionally run insight_draft (opencode),
# stage updates, then exit 1 so the user re-runs git commit (same pattern as catalog-drift).
#
# Environment:
#   SKIP_INSIGHT_DRAFT_PRECOMMIT=1  — only create missing stubs; never run opencode
#   (unset)                         — if opencode is on PATH and the insight still has
#                                     <!-- TODO: --> placeholders, run insight_draft.py
#
# Requires: make docs-setup (scripts/docgen/.venv)
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi
cd "$REPO_ROOT"

VENV="scripts/docgen/.venv/bin/python3"
if [[ ! -x "$VENV" ]]; then
  echo "WARNING: docgen venv missing — skipping service-insight sync. Run: make docs-setup" >&2
  exit 0
fi

RAW=()
for f in "$@"; do
  [[ -z "$f" ]] && continue
  case "$f" in
    apps/base/*)
      slug="$(echo "$f" | cut -d/ -f3)"
      [[ -n "$slug" ]] && RAW+=("$slug")
      ;;
    base/services/*.yaml|base/services/*.yml)
      b="$(basename "$f")"
      slug="${b%.yaml}"
      slug="${slug%.yml}"
      RAW+=("$slug")
      ;;
  esac
done

if [[ ${#RAW[@]} -eq 0 ]]; then
  exit 0
fi

SLUGS="$(printf '%s\n' "${RAW[@]}" | sort -u)"
if [[ -z "${SLUGS// }" ]]; then
  exit 0
fi

VALID=()
while IFS= read -r slug; do
  [[ -z "$slug" ]] && continue
  if "$VENV" -c "import json,sys; c=json.load(open('service-catalog.json')); s=c['services'].get('$slug'); sys.exit(0 if s and s.get('enabled') else 1)" 2>/dev/null; then
    VALID+=("$slug")
  fi
done <<<"$SLUGS"

if [[ ${#VALID[@]} -eq 0 ]]; then
  exit 0
fi

echo "pre-commit: service-insight sync for: ${VALID[*]}" >&2

"$VENV" scripts/docgen/make_stubs.py "${VALID[@]}"

STAGED=0
for slug in "${VALID[@]}"; do
  p="service-insights/${slug}.yaml"
  [[ -f "$p" ]] || continue
  if [[ -n "$(git status --porcelain "$p" 2>/dev/null || true)" ]]; then
    git add -- "$p"
    STAGED=1
    echo "  staged $p" >&2
  fi
done

run_draft=true
if [[ "${SKIP_INSIGHT_DRAFT_PRECOMMIT:-}" =~ ^(1|true|yes)$ ]]; then
  run_draft=false
fi

if $run_draft; then
  if ! command -v opencode &>/dev/null; then
    for slug in "${VALID[@]}"; do
      path="service-insights/${slug}.yaml"
      if [[ -f "$path" ]] && grep -q '<!-- TODO:' "$path" 2>/dev/null; then
        echo "WARNING: $path still has TODO placeholders; install opencode or run: make insight-draft SVC=$slug" >&2
        echo "WARNING: Or set SKIP_INSIGHT_DRAFT_PRECOMMIT=1 to silence this for commits with stubs only." >&2
      fi
    done
  else
    for slug in "${VALID[@]}"; do
      path="service-insights/${slug}.yaml"
      [[ -f "$path" ]] || continue
      if ! grep -q '<!-- TODO:' "$path" 2>/dev/null; then
        continue
      fi
      echo "  running insight_draft.py $slug (opencode)…" >&2
      "$VENV" scripts/docgen/insight_draft.py "$slug"
    done
    for slug in "${VALID[@]}"; do
      p="service-insights/${slug}.yaml"
      [[ -f "$p" ]] || continue
      if [[ -n "$(git status --porcelain "$p" 2>/dev/null || true)" ]]; then
        git add -- "$p"
        STAGED=1
        echo "  staged $p" >&2
      fi
    done
  fi
fi

SCHEMA_ARGS=()
for slug in "${VALID[@]}"; do
  p="service-insights/${slug}.yaml"
  [[ -f "$p" ]] && SCHEMA_ARGS+=("$p")
done
if [[ ${#SCHEMA_ARGS[@]} -gt 0 ]]; then
  "$VENV" scripts/docgen/insight_schema.py "${SCHEMA_ARGS[@]}"
fi

if [[ "$STAGED" -ne 0 ]]; then
  echo "pre-commit: service-insights updated and staged — re-run git commit to include them." >&2
  exit 1
fi

exit 0
