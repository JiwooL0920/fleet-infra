#!/usr/bin/env bash
# update-docs.sh — Deterministic docs-sync orchestrator for flux-infra.
#
# Runs the Python pipeline (catalog → render → validate) and opens a cross-repo PR
# in the blog repository with the freshly rendered pages.
#
# Usage:
#   scripts/update-docs.sh [all]
#
#   (no args)  Incremental: only render services changed since last sync watermark
#   all        Full: regenerate all enabled services and all rollup pages
#
# Prerequisites:
#   - gh  (GitHub CLI, authenticated)
#   - jq  (for watermark JSON read/write)
#   - Blog repo cloned at $BLOG_REPO_DIR
#   - Python 3 venv at scripts/docgen/.venv (run: make docs-setup)
#
# Environment variables:
#   BLOG_REPO_DIR    Path to local blog clone (default: ~/Project/jiwool0920.github.io)
#   BLOG_REPO_GH     GitHub repo slug   (default: JiwooL0920/jiwool0920.github.io)

set -o errexit
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_info()  { echo -e "${GREEN}INFO${NC}  $1" >&2; }
echo_warn()  { echo -e "${YELLOW}WARN${NC}  $1" >&2; }
echo_error() { echo -e "${RED}ERROR${NC} $1" >&2; }
echo_step()  { echo -e "${CYAN}----${NC}  $1" >&2; }

# ── Configuration ──────────────────────────────────────────────────────────────
MODE="${1:-incremental}"
BLOG_REPO_DIR="${BLOG_REPO_DIR:-${HOME}/Project/jiwool0920.github.io}"
BLOG_REPO_GH="${BLOG_REPO_GH:-JiwooL0920/jiwool0920.github.io}"
TODAY="$(date '+%Y-%m-%d')"

FLEET_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
FLEET_COMMIT="$(git -C "$FLEET_ROOT" rev-parse --short HEAD)"
PYTHON="${FLEET_ROOT}/scripts/docgen/.venv/bin/python3"
CATALOG_PY="${FLEET_ROOT}/scripts/docgen/catalog.py"
RENDER_PY="${FLEET_ROOT}/scripts/docgen/render.py"
VALIDATE_PY="${FLEET_ROOT}/scripts/docgen/validate.py"
CATALOG_JSON="${FLEET_ROOT}/service-catalog.json"

BLOG_FLUX_DOCS="${BLOG_REPO_DIR}/docs/projects/flux-infra"
BLOG_COMPONENTS="${BLOG_FLUX_DOCS}/components"
DOCS_STATE_FILE="${BLOG_FLUX_DOCS}/.docs-sync-state.json"
BLOG_MKDOCS="${BLOG_REPO_DIR}/mkdocs.yml"
APPLY_TO_BLOG_SH="${FLEET_ROOT}/scripts/docgen/apply_to_blog.sh"

RENDER_OUTPUT="$(mktemp -d /tmp/flux-infra-docs-XXXX)"
cleanup() { rm -rf "$RENDER_OUTPUT"; }
trap cleanup EXIT

# ── Pre-flight checks ──────────────────────────────────────────────────────────
check_prerequisites() {
    local missing=0
    for cmd in gh jq; do
        if ! command -v "$cmd" &>/dev/null; then
            echo_error "Required tool not found: $cmd"
            missing=1
        fi
    done
    if [[ ! -f "$PYTHON" ]]; then
        echo_error "Python venv not found. Run: make docs-setup"
        missing=1
    fi
    if [[ ! -d "$BLOG_REPO_DIR" ]]; then
        echo_error "Blog repo not found at $BLOG_REPO_DIR"
        echo_error "Clone it with: git clone git@github.com:${BLOG_REPO_GH}.git $BLOG_REPO_DIR"
        missing=1
    fi
    [[ $missing -eq 0 ]] || exit 1
}

# ── Watermark helpers ──────────────────────────────────────────────────────────
read_watermark() {
    if [[ -f "$DOCS_STATE_FILE" ]]; then
        jq -r '.last_synced_commit // ""' "$DOCS_STATE_FILE" 2>/dev/null || echo ""
    fi
}

# ── Changed services detection ─────────────────────────────────────────────────
changed_services_since() {
    local since_commit="$1"
    if [[ -z "$since_commit" ]]; then
        echo ""
        return
    fi
    # Find service slugs whose manifests changed since the watermark commit
    git -C "$FLEET_ROOT" diff --name-only "${since_commit}..HEAD" -- \
        'apps/base/' 'base/services/' 'service-insights/' 2>/dev/null \
        | awk -F'/' '{print $2}' \
        | sed 's/\.yaml$//' \
        | sort -u \
        | tr '\n' ',' \
        | sed 's/,$//'
}

# ── Step 1: Extract catalog ────────────────────────────────────────────────────
run_catalog() {
    echo_step "Extracting service catalog..."
    "$PYTHON" "$CATALOG_PY"
    echo_info "service-catalog.json updated ($(jq '.services | length' "$CATALOG_JSON") services)"
}

# ── Step 2: Render pages ───────────────────────────────────────────────────────
run_render() {
    local services_filter="$1"
    echo_step "Rendering documentation pages..."
    local extra_args=()
    if [[ -n "$services_filter" ]]; then
        echo_info "Incremental render — services: $services_filter"
        extra_args=(--services "$services_filter")
    else
        echo_info "Full render — all enabled services"
    fi
    "$PYTHON" "$RENDER_PY" --output-dir "$RENDER_OUTPUT" "${extra_args[@]}"
    echo_info "Rendered to $RENDER_OUTPUT"
}

# ── Step 3: Validate ──────────────────────────────────────────────────────────
run_validate() {
    echo_step "Validating rendered pages..."
    if ! "$PYTHON" "$VALIDATE_PY" --docs-dir "$RENDER_OUTPUT"; then
        echo_error "Validation failed — fix errors before opening PR"
        exit 1
    fi
    echo_info "Validation passed"
}

# ── Step 4: Sync to blog repo on a clean branch ───────────────────────────────
sync_to_blog() {
    echo_step "Syncing rendered files to blog repo..."

    # Ensure blog repo is up-to-date with origin/main
    git -C "$BLOG_REPO_DIR" fetch origin --quiet
    git -C "$BLOG_REPO_DIR" checkout main --quiet
    git -C "$BLOG_REPO_DIR" reset --hard origin/main --quiet

    # Create a clean branch for the PR
    local branch="docs-sync/flux-infra-${FLEET_COMMIT}-${TODAY}"
    if git -C "$BLOG_REPO_DIR" show-ref --quiet "refs/heads/$branch"; then
        echo_warn "Branch $branch already exists — deleting and recreating"
        git -C "$BLOG_REPO_DIR" branch -D "$branch" --quiet
    fi
    git -C "$BLOG_REPO_DIR" checkout -b "$branch" --quiet

    echo_step "Applying rendered docs to blog tree..."
    local copied
    copied="$("$APPLY_TO_BLOG_SH" \
        --blog-dir "$BLOG_REPO_DIR" \
        --render-dir "$RENDER_OUTPUT" \
        --watermark-commit "$FLEET_COMMIT" \
        --sync-date "$TODAY" \
        --python "$PYTHON" | tail -1)"
    copied="${copied#COPIED_COMPONENT_MD_FILES=}"
    echo_info "Copied $copied component markdown file(s) into blog repo"

    # Stage and commit
    git -C "$BLOG_REPO_DIR" add \
        "${BLOG_MKDOCS}" \
        "${BLOG_FLUX_DOCS}/" \
        "${BLOG_COMPONENTS}/"

    if git -C "$BLOG_REPO_DIR" diff --cached --quiet; then
        echo_info "No changes to commit — docs are already up to date"
        git -C "$BLOG_REPO_DIR" checkout main --quiet
        echo "__no_changes__"
        return 0
    fi

    git -C "$BLOG_REPO_DIR" commit -m "docs(flux-infra): sync component pages from flux-infra@${FLEET_COMMIT}

- Generated from service-catalog.json (catalog_sha: $(jq -r '._meta.catalog_sha' "$CATALOG_JSON"))
- ${copied} component pages updated
- Rendered at: ${TODAY}

Source: https://github.com/JiwooL0920/flux-infra/commit/${FLEET_COMMIT}" --quiet

    echo_info "Committed $copied component page(s) on branch $branch"
    echo "$branch"
}

# ── Step 5: Push and open PR ──────────────────────────────────────────────────
open_pr() {
    local branch="$1"
    echo_step "Pushing branch and opening PR..."

    git -C "$BLOG_REPO_DIR" push origin "$branch" --quiet

    local catalog_sha
    catalog_sha="$(jq -r '._meta.catalog_sha' "$CATALOG_JSON")"
    local pr_body
    pr_body="$(cat <<EOF
## Flux-Infra Docs Sync

Deterministically rendered from [flux-infra](https://github.com/JiwooL0920/flux-infra) at commit \`${FLEET_COMMIT}\`.

| Field | Value |
|---|---|
| **catalog_sha** | \`${catalog_sha}\` |
| **Source commit** | [\`${FLEET_COMMIT}\`](https://github.com/JiwooL0920/flux-infra/commit/${FLEET_COMMIT}) |
| **Rendered at** | ${TODAY} |
| **Mode** | ${MODE} |

### What changed

Pages generated from \`service-catalog.json\` + \`service-insights/*.yaml\`.
All config values (chart version, resource requests, replica counts) are sourced directly
from environment.env files — not hand-typed.

### Review checklist
- [ ] Config table values look correct for dev and prod
- [ ] No unexpected TODO placeholders in services that should be complete
- [ ] Mermaid diagrams render correctly in the preview
EOF
)"

    local pr_url
    pr_url="$(gh pr create \
        --repo "$BLOG_REPO_GH" \
        --base main \
        --head "$branch" \
        --title "docs(flux-infra): sync component pages from @${FLEET_COMMIT}" \
        --body "$pr_body" \
        2>&1)"

    echo_info "PR opened: $pr_url"
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    echo_info "flux-infra docs-sync (mode: $MODE, commit: $FLEET_COMMIT)"
    echo ""

    check_prerequisites

    # Determine which services to render
    local services_filter=""
    if [[ "$MODE" != "all" ]]; then
        local watermark
        watermark="$(read_watermark)"
        if [[ -n "$watermark" ]]; then
            services_filter="$(changed_services_since "$watermark")"
            if [[ -z "$services_filter" ]]; then
                echo_info "No service changes since watermark $watermark — nothing to sync"
                exit 0
            fi
            echo_info "Changed services since $watermark: $services_filter"
        else
            echo_info "No watermark found — running full sync"
        fi
    fi

    run_catalog
    run_render "$services_filter"
    run_validate

    local branch
    branch="$(sync_to_blog)"

    if [[ "$branch" == "__no_changes__" ]]; then
        echo_info "Nothing to publish — blog is already up to date."
        exit 0
    fi

    open_pr "$branch"

    echo ""
    echo_info "Done. Review the PR, then merge to publish."
}

main "$@"
