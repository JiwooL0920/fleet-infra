#!/usr/bin/env bash
# apply_to_blog.sh — Copy rendered flux-infra docs into a blog repo checkout (no git).
#
# Used by scripts/update-docs.sh (local) and .github/workflows/docs-sync.yml (CI).
#
# Usage:
#   ./scripts/docgen/apply_to_blog.sh \
#       --blog-dir /path/to/jiwool0920.github.io \
#       --render-dir /path/to/render-output \
#       --watermark-commit <short-sha> \
#       --sync-date YYYY-MM-DD \
#       [--python /path/to/python3]
#
# Requires: python3 + PyYAML (same as inject_nav.py)

set -o errexit
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INJECT_NAV_PY="${SCRIPT_DIR}/inject_nav.py"

BLOG_DIR=""
RENDER_DIR=""
WATERMARK_COMMIT=""
SYNC_DATE=""
PYTHON_BIN="${PYTHON_BIN:-python3}"

usage() {
    echo "Usage: $0 --blog-dir <path> --render-dir <path> --watermark-commit <sha> --sync-date YYYY-MM-DD [--python /path/to/python3]" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --blog-dir) BLOG_DIR="$2"; shift 2 ;;
        --render-dir) RENDER_DIR="$2"; shift 2 ;;
        --watermark-commit) WATERMARK_COMMIT="$2"; shift 2 ;;
        --sync-date) SYNC_DATE="$2"; shift 2 ;;
        --python) PYTHON_BIN="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

[[ -n "$BLOG_DIR" && -n "$RENDER_DIR" && -n "$WATERMARK_COMMIT" && -n "$SYNC_DATE" ]] || usage

BLOG_DIR="$(cd "$BLOG_DIR" && pwd)"
RENDER_DIR="$(cd "$RENDER_DIR" && pwd)"

BLOG_FLUX_DOCS="${BLOG_DIR}/docs/projects/flux-infra"
BLOG_COMPONENTS="${BLOG_FLUX_DOCS}/components"
BLOG_MKDOCS="${BLOG_DIR}/mkdocs.yml"
DOCS_STATE_FILE="${BLOG_FLUX_DOCS}/.docs-sync-state.json"
NAV_FRAGMENT="${RENDER_DIR}/nav.yml"

if [[ ! -d "$RENDER_DIR/components" ]]; then
    echo "ERROR: render dir has no components/: $RENDER_DIR" >&2
    exit 1
fi

mkdir -p "$BLOG_COMPONENTS"

# Remove stale *.yaml.md files from older pipeline iterations
while IFS= read -r -d '' stale; do
    rm -f "$stale"
done < <(find "$BLOG_COMPONENTS" -maxdepth 1 -name "*.yaml.md" -print0 2>/dev/null || true)

COPIED=0
for f in "${RENDER_DIR}/components/"*.md; do
    [[ -f "$f" ]] || continue
    cp "$f" "$BLOG_COMPONENTS/"
    COPIED=$((COPIED + 1))
done

for rollup in index.md architecture.md; do
    src="${RENDER_DIR}/${rollup}"
    if [[ -f "$src" ]]; then
        cp "$src" "${BLOG_FLUX_DOCS}/${rollup}"
    fi
done

if [[ -f "$NAV_FRAGMENT" && -f "$BLOG_MKDOCS" ]]; then
    "$PYTHON_BIN" "$INJECT_NAV_PY" --nav-fragment "$NAV_FRAGMENT" --mkdocs "$BLOG_MKDOCS" >&2
else
    echo "WARN: skipping nav injection (nav.yml=$NAV_FRAGMENT mkdocs=$BLOG_MKDOCS)" >&2
fi

mkdir -p "$(dirname "$DOCS_STATE_FILE")"
echo "{\"last_synced_commit\": \"${WATERMARK_COMMIT}\", \"synced_at\": \"${SYNC_DATE}\"}" > "$DOCS_STATE_FILE"

# Single line for callers that need the count (e.g. commit message)
echo "COPIED_COMPONENT_MD_FILES=${COPIED}"
