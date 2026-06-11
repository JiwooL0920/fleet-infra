#!/usr/bin/env bash

# Keeps docs/projects/flux-infra in jiwool0920.github.io in sync with the
# current state of fleet-infra services using local opencode and a cross-repo PR.
#
# Usage:
#   scripts/update-docs.sh [all]
#
#   (no args)  Incremental: reconcile services changed since the stored watermark
#   all        Full: reconcile every enabled service and regenerate all index pages
#
# Prerequisites:
#   - opencode installed and authenticated (uses your existing opencode.jsonc config)
#   - gh installed and authenticated
#   - jq installed (for watermark JSON read/write)
#   - Blog repo cloned at $BLOG_REPO_DIR (default: ~/Project/jiwool0920.github.io)
#
# Environment:
#   BLOG_REPO_DIR    Path to local blog clone (default: ~/Project/jiwool0920.github.io)
#   BLOG_REPO_GH     GitHub repo slug (default: JiwooL0920/jiwool0920.github.io)
#   DOCS_SYNC_MODEL  opencode model override; omit to use opencode.jsonc default

set -o errexit
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_info()  { echo -e "${GREEN}INFO${NC}  $1"; }
echo_warn()  { echo -e "${YELLOW}WARN${NC}  $1"; }
echo_error() { echo -e "${RED}ERROR${NC} $1"; }
echo_step()  { echo -e "${CYAN}----${NC}  $1"; }

# ── Configuration ──────────────────────────────────────────────────────────────
MODE="${1:-incremental}"
BLOG_REPO_DIR="${BLOG_REPO_DIR:-${HOME}/Project/jiwool0920.github.io}"
BLOG_REPO_GH="${BLOG_REPO_GH:-JiwooL0920/jiwool0920.github.io}"
TODAY="$(date '+%Y-%m-%d')"
DOCS_STATE_FILE="${BLOG_REPO_DIR}/docs/projects/flux-infra/.docs-sync-state.json"
COMPONENTS_DIR="${BLOG_REPO_DIR}/docs/projects/flux-infra/components"
FLUX_DOCS_DIR="${BLOG_REPO_DIR}/docs/projects/flux-infra"
EXEMPLAR_PAGE="${COMPONENTS_DIR}/redis.md"
KUSTOMIZATION="base/services/kustomization.yaml"
ERR_FILE="/tmp/update-docs-opencode-err.txt"

# Temp dir for prompts and outputs — cleaned up on exit
TMPDIR_WORK="$(mktemp -d /tmp/update-docs-XXXX)"
cleanup() { rm -rf "$TMPDIR_WORK"; }
trap cleanup EXIT

# ── Service slug mapping (bash 3.2 compatible — case-based) ───────────────────
# Returns the component page slug for a given service name.
# Services not explicitly mapped use their own name as the slug.
service_to_slug_map() {
    case "$1" in
        redis-sentinel)              echo "redis" ;;
        postgresql-cluster)          echo "postgresql" ;;
        pgadmin4)                    echo "pgadmin" ;;
        opentelemetry-collector)     echo "opentelemetry" ;;
        scylla-cluster)              echo "scylladb" ;;
        external-secrets-operator)   echo "external-secrets" ;;
        external-secrets-config)     echo "external-secrets" ;;  # shares page
        traefik-config)              echo "traefik" ;;            # shares page
        agentgateway-config)         echo "agentgateway" ;;       # shares page
        *)                           echo "$1" ;;
    esac
}

# Returns 1 if the service is internal glue with no standalone component page.
is_no_standalone_page() {
    case "$1" in
        grafana-sa-setup|gateway-api-crds|node-image-gc) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Helpers ────────────────────────────────────────────────────────────────────
service_to_slug() {
    service_to_slug_map "$1"
}

run_opencode() {
    local prompt_file="$1"
    local output_file="$2"
    local description="$3"

    echo_info "  opencode: $description"

    local model_flag=()
    if [[ -n "${DOCS_SYNC_MODEL:-}" ]]; then
        model_flag=(-m "$DOCS_SYNC_MODEL")
    fi

    if ! opencode run \
            "Write the documentation described in the attached file." \
            -f "$prompt_file" \
            "${model_flag[@]}" \
            --dangerously-skip-permissions \
            < /dev/null \
            > "$output_file" \
            2>"$ERR_FILE"; then
        echo_error "opencode failed for: $description"
        echo_error "stderr:"
        cat "$ERR_FILE" >&2
        return 1
    fi

    # Strip ANSI codes
    sed -i '' 's/\x1b\[[0-9;]*[mGKHF]//g' "$output_file" 2>/dev/null || \
        sed -i 's/\x1b\[[0-9;]*[mGKHF]//g' "$output_file" 2>/dev/null || true

    # Remove leading blank lines
    sed -i '' '/./,$!d' "$output_file" 2>/dev/null || \
        sed -i '/./,$!d' "$output_file" 2>/dev/null || true

    local lines
    lines=$(wc -l < "$output_file")
    echo_info "  Generated: ${lines} lines -> $output_file"
}

# ── Prerequisites check ────────────────────────────────────────────────────────
check_prerequisites() {
    local missing=()
    command -v opencode &>/dev/null || missing+=("opencode")
    command -v gh       &>/dev/null || missing+=("gh")
    command -v jq       &>/dev/null || missing+=("jq")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo_error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    if [[ ! -d "$BLOG_REPO_DIR" ]]; then
        echo_error "Blog repo not found at: $BLOG_REPO_DIR"
        exit 1
    fi

    if ! gh auth status &>/dev/null; then
        echo_error "gh is not authenticated. Run: gh auth login"
        exit 1
    fi
}

# ── Read watermark ─────────────────────────────────────────────────────────────
read_watermark() {
    if [[ "$MODE" == "all" ]]; then
        echo "all"
        return
    fi

    if [[ ! -f "$DOCS_STATE_FILE" ]]; then
        echo_warn "No watermark found at $DOCS_STATE_FILE — running full reconcile"
        MODE="all"
        echo "all"
        return
    fi

    local sha
    sha=$(jq -r '.fleet_infra_commit // empty' "$DOCS_STATE_FILE" 2>/dev/null || true)

    if [[ -z "$sha" ]]; then
        echo_warn "Watermark file exists but has no fleet_infra_commit — running full reconcile"
        MODE="all"
        echo "all"
        return
    fi

    # Verify the SHA exists in this repo
    if ! git rev-parse --verify "$sha^{commit}" &>/dev/null; then
        echo_warn "Watermark SHA $sha not found in repo — running full reconcile"
        MODE="all"
        echo "all"
        return
    fi

    echo "$sha"
}

# ── Enumerate enabled services ─────────────────────────────────────────────────
enumerate_services() {
    # Parse uncommented resource lines from kustomization.yaml.
    # Use awk to extract field $2 (the filename, stops at whitespace before any comment),
    # then strip the .yaml/.yml extension with sed -E (BSD sed compatible).
    grep -v '^\s*#' "$KUSTOMIZATION" \
        | grep -E '^\s*-\s+[a-z][a-z0-9-]+\.ya?ml' \
        | awk '{print $2}' \
        | sed -E 's/\.ya?ml$//' \
        | grep -v '^$' \
        | sort -u
}

# ── Compute affected service set ───────────────────────────────────────────────
# Populates the global AFFECTED_SERVICES array.
AFFECTED_SERVICES=()

compute_affected() {
    local watermark="$1"
    local all_services_str="$2"
    AFFECTED_SERVICES=()

    if [[ "$watermark" == "all" ]]; then
        while IFS= read -r svc; do
            [[ -z "$svc" ]] && continue
            AFFECTED_SERVICES+=("$svc")
        done <<< "$all_services_str"
        return
    fi

    echo_step "Computing services changed since $watermark"

    # Files changed in fleet-infra since watermark
    local changed_files
    changed_files=$(git diff --name-only "${watermark}..HEAD" -- apps/base/ base/services/ 2>/dev/null || true)

    if [[ -z "$changed_files" ]]; then
        echo_info "No infra changes since watermark"
        return
    fi

    # Extract unique service names from changed paths
    local seen=()
    while IFS= read -r file; do
        local svc=""
        if [[ "$file" =~ ^apps/base/([^/]+)/ ]]; then
            svc="${BASH_REMATCH[1]}"
        elif [[ "$file" =~ ^base/services/([^/]+)\.ya?ml ]]; then
            svc="${BASH_REMATCH[1]}"
        fi

        [[ -z "$svc" ]] && continue

        # Only include services that are currently enabled
        if echo "$all_services_str" | grep -qx "$svc"; then
            if [[ ! " ${seen[*]} " =~ [[:space:]]${svc}[[:space:]] ]]; then
                seen+=("$svc")
                AFFECTED_SERVICES+=("$svc")
            fi
        fi
    done <<< "$changed_files"
}

# ── Read manifest files for a service ─────────────────────────────────────────
collect_manifests() {
    local svc="$1"
    local output=""

    # apps/base/<svc>/ — HelmRelease, kustomization, main configs (cap at 6 files)
    local app_dir="apps/base/${svc}"
    if [[ -d "$app_dir" ]]; then
        local count=0
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            ((count++)) || true
            if [[ $count -gt 6 ]]; then
                output+="### (additional files truncated for brevity)\n\n"
                break
            fi
            output+="### File: ${f}\n\n\`\`\`yaml\n$(head -c 3000 "$f")\n\`\`\`\n\n"
        done < <(find "$app_dir" -maxdepth 2 \( -name "*.yaml" -o -name "*.yml" \) | sort)
    fi

    # base/services/<svc>.yaml — dependsOn and layer context
    local svc_file="base/services/${svc}.yaml"
    if [[ -f "$svc_file" ]]; then
        output+="### File: ${svc_file}\n\n\`\`\`yaml\n$(cat "$svc_file")\n\`\`\`\n\n"
    fi

    echo -e "$output"
}

# ── Generate a component page ──────────────────────────────────────────────────
generate_component_page() {
    local svc="$1"
    local page_path="$2"
    local slug
    slug=$(service_to_slug "$svc")
    local prompt_file="${TMPDIR_WORK}/prompt-${svc}.txt"
    local output_file="${TMPDIR_WORK}/output-${svc}.md"

    echo_step "Generating component page: $slug ($svc)"

    # Gather manifests
    local manifests
    manifests=$(collect_manifests "$svc")

    # Existing page content (for refresh mode)
    local existing_content=""
    if [[ -f "$page_path" ]]; then
        existing_content=$(cat "$page_path")
    fi

    # Exemplar page
    local exemplar_content=""
    if [[ -f "$EXEMPLAR_PAGE" ]]; then
        exemplar_content=$(cat "$EXEMPLAR_PAGE")
    fi

    cat > "$prompt_file" <<PROMPT
You are writing a technical reference documentation page for a homelab Kubernetes platform.
The platform is "fleet-infra" — a Flux CD GitOps setup managing services on a local Kind cluster.
Author: Jiwoo Lee, platform engineer. Style: direct, precise, technical.

## Service to document
Service name: ${svc}
Component page slug: ${slug}

## Kubernetes manifests (the source of truth)

${manifests}

## Exemplar page (match this structure and style exactly)

${exemplar_content}

## Existing page content (if present — REFRESH, do not rewrite from scratch; preserve any accurate manual additions)

${existing_content}

---

Write a complete Markdown reference page for the service.

Structure (match the exemplar):
1. # <Service Name> (H1 title)
2. One-sentence description
3. ## Overview — property table with: Namespace, Type, Layer, Dependencies, Access
4. ## Purpose — 2-3 sentences on what this service does and why it exists
5. ## Features — bullet list of key features
6. ## Architecture — a mermaid diagram if the service has non-trivial internal topology
7. ## Connection — how to connect to / use the service (port-forward + app config)
8. ## Environment Configuration — dev vs prod table (replicas, storage, resources)
9. ## Verification — kubectl commands to confirm it is healthy
10. ## Troubleshooting — 2-3 common failure scenarios with diagnostic commands
11. ## Related — links to related component pages using relative paths like [Redis](redis.md)

Use information from the manifests as the source of truth for namespaces, helm chart versions,
resource limits, dependencies (from dependsOn in the service kustomization), and access URLs.
Output ONLY the Markdown file body — no preamble, no explanation outside the page.
PROMPT

    run_opencode "$prompt_file" "$output_file" "component page for $svc"

    # Validate output is non-empty markdown
    if [[ ! -s "$output_file" ]]; then
        echo_error "Empty output for $svc — skipping"
        return 1
    fi

    # Write to destination
    mkdir -p "$(dirname "$page_path")"
    cp "$output_file" "$page_path"
    echo_info "  Written: $page_path"
}

# ── Generate roll-up pages ─────────────────────────────────────────────────────
generate_rollup_pages() {
    local all_services_str="$1"

    echo_step "Regenerating index, architecture, and nav"

    # Build service inventory: slug, title (H1), one-liner, layer, access
    local inventory=""
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        local slug
        slug=$(service_to_slug "$svc")
        # Skip glue services with no standalone page
        is_no_standalone_page "$svc" && continue

        local page="${COMPONENTS_DIR}/${slug}.md"
        local h1="" summary="" layer="" access=""
        if [[ -f "$page" ]]; then
            h1=$(grep -m1 '^# ' "$page" | sed 's/^# //')
            summary=$(grep -A1 '^# ' "$page" | tail -1)
            # Extract layer from property table
            layer=$(grep -i '^\*\*Layer\*\*\|^| \*\*Layer\*\*' "$page" | head -1 | sed 's/.*|\s*//; s/\s*|.*//')
            access=$(grep -i '^\*\*Access\*\*\|^| \*\*Access\*\*' "$page" | head -1 | sed 's/.*|\s*//; s/\s*|.*//')
        else
            h1="$svc"
            summary="(page not yet generated)"
        fi
        inventory+="| $svc | $slug | $h1 | $summary | $layer | $access |\n"
    done <<< "$all_services_str"

    # Count active enabled services (exclude glue services)
    local total=0
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        is_no_standalone_page "$svc" && continue
        ((total++)) || true
    done <<< "$all_services_str"

    # Also build dependency graph info from service kustomization files
    local dep_info=""
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        local svc_file="base/services/${svc}.yaml"
        if [[ -f "$svc_file" ]]; then
            local deps
            deps=$(grep -A5 'dependsOn:' "$svc_file" 2>/dev/null | grep '^\s*- name:' | sed 's/.*name:\s*//' | tr '\n' ',' | sed 's/,$//')
            dep_info+="$svc: depends_on=[${deps}]\n"
        fi
    done <<< "$all_services_str"

    # Read current index/architecture/nav files
    local current_index current_components_index current_architecture current_nav
    current_index=$(cat "${FLUX_DOCS_DIR}/index.md" 2>/dev/null || echo "")
    current_components_index=$(cat "${COMPONENTS_DIR}/index.md" 2>/dev/null || echo "")
    current_architecture=$(cat "${FLUX_DOCS_DIR}/architecture.md" 2>/dev/null || echo "")
    current_nav=$(grep -n "flux-infra\|components" "${BLOG_REPO_DIR}/mkdocs.yml" 2>/dev/null | head -30 || echo "")

    # ── Roll-up prompt ──────────────────────────────────────────────────────
    local rollup_prompt="${TMPDIR_WORK}/prompt-rollup.txt"
    local rollup_output="${TMPDIR_WORK}/output-rollup.txt"

    cat > "$rollup_prompt" <<PROMPT
You are updating documentation roll-up pages for a homelab Kubernetes platform called "fleet-infra".
The platform uses Flux CD GitOps on a local Kind cluster.

## Current enabled services (${total} active, excluding internal glue services)

The table below lists every enabled service, its component page slug, title, layer, and access URL.

| service_name | slug | title | summary | layer | access |
|---|---|---|---|---|---|
$(echo -e "$inventory")

## Service dependency graph (from Flux dependsOn declarations)

$(echo -e "$dep_info")

## Current docs/projects/flux-infra/index.md (UPDATE THIS — fix counts and service tables)

${current_index}

## Current docs/projects/flux-infra/components/index.md (UPDATE THIS — fix layer tables, service count, mermaid graph)

${current_components_index}

## Current docs/projects/flux-infra/architecture.md (UPDATE THIS — fix layer subgraphs to include all services)

${current_architecture}

## Current mkdocs.yml Components nav block (relevant lines shown; UPDATE THE LIST to add missing slugs alphabetically within their layer)

${current_nav}

---

Produce FOUR files, each separated by a delimiter line "===FILE: <filename>===".

Output format exactly:
===FILE: index.md===
<full updated content of docs/projects/flux-infra/index.md>
===FILE: components/index.md===
<full updated content of docs/projects/flux-infra/components/index.md>
===FILE: architecture.md===
<full updated content of docs/projects/flux-infra/architecture.md>
===FILE: mkdocs-nav-snippet.txt===
<the updated Components nav block only (indented as it appears in mkdocs.yml), starting from '          - Components:' and ending with '          - Runbooks:'>

Rules:
- Fix service counts to match the actual total (${total}).
- Add every slug from the inventory table to the appropriate layer in components/index.md.
- Add every new slug to the mkdocs nav snippet in the correct layer position.
- Update mermaid diagrams in components/index.md and architecture.md to include all services.
- Preserve all content in existing pages that isn't about service counts/lists/layers.
- Do NOT delete any section that exists in the current pages.
- Output ONLY the four file blocks — no preamble, no explanation.
PROMPT

    run_opencode "$rollup_prompt" "$rollup_output" "roll-up pages (index, architecture, nav)"

    # Parse and write each file from the delimiter-separated output
    echo_step "Writing roll-up files"
    local current_file=""
    local current_content=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^===FILE:\ (.+)=== ]]; then
            # Write previous file
            if [[ -n "$current_file" && -n "$current_content" ]]; then
                write_rollup_file "$current_file" "$current_content"
            fi
            current_file="${BASH_REMATCH[1]}"
            current_content=""
        else
            current_content+="${line}"$'\n'
        fi
    done < "$rollup_output"

    # Write final file
    if [[ -n "$current_file" && -n "$current_content" ]]; then
        write_rollup_file "$current_file" "$current_content"
    fi
}

write_rollup_file() {
    local fname="$1"
    local content="$2"

    case "$fname" in
        index.md)
            echo "$content" > "${FLUX_DOCS_DIR}/index.md"
            echo_info "  Written: ${FLUX_DOCS_DIR}/index.md"
            ;;
        components/index.md)
            echo "$content" > "${COMPONENTS_DIR}/index.md"
            echo_info "  Written: ${COMPONENTS_DIR}/index.md"
            ;;
        architecture.md)
            echo "$content" > "${FLUX_DOCS_DIR}/architecture.md"
            echo_info "  Written: ${FLUX_DOCS_DIR}/architecture.md"
            ;;
        mkdocs-nav-snippet.txt)
            # Patch mkdocs.yml: replace the Components nav block
            patch_mkdocs_nav "$content"
            ;;
        *)
            echo_warn "Unrecognized file from rollup output: $fname — skipping"
            ;;
    esac
}

# ── Patch mkdocs.yml nav ───────────────────────────────────────────────────────
patch_mkdocs_nav() {
    local nav_snippet="$1"
    local mkdocs="${BLOG_REPO_DIR}/mkdocs.yml"

    # Find the line range of the Components block in mkdocs.yml
    local start_line end_line
    start_line=$(grep -n '^\s*- Components:' "$mkdocs" | head -1 | cut -d: -f1)
    end_line=$(grep -n '^\s*- Runbooks:' "$mkdocs" | head -1 | cut -d: -f1)

    if [[ -z "$start_line" || -z "$end_line" ]]; then
        echo_warn "Could not locate Components block in mkdocs.yml — writing nav snippet as separate file for manual merge"
        echo "$nav_snippet" > "${BLOG_REPO_DIR}/docs/projects/flux-infra/.mkdocs-nav-patch.txt"
        return
    fi

    # Build the new file: lines before Components + new snippet + lines from Runbooks onward
    local before after
    before=$(head -n "$((start_line - 1))" "$mkdocs")
    after=$(tail -n "+${end_line}" "$mkdocs")

    # Strip trailing newlines from snippet, then reassemble
    printf '%s\n%s\n%s\n' "$before" "$nav_snippet" "$after" > "${mkdocs}.tmp"
    mv "${mkdocs}.tmp" "$mkdocs"
    echo_info "  Patched: $mkdocs nav (lines $start_line-$end_line)"
}

# ── Advance watermark ──────────────────────────────────────────────────────────
advance_watermark() {
    local current_sha
    current_sha=$(git rev-parse HEAD)
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq -n \
        --arg sha "$current_sha" \
        --arg ts "$now" \
        '{ fleet_infra_commit: $sha, synced_at: $ts }' \
        > "$DOCS_STATE_FILE"

    echo_info "Watermark advanced to $current_sha"
}

# ── Create PR in blog repo ─────────────────────────────────────────────────────
create_pr() {
    local affected_services=("$@")
    echo_step "Preparing blog repo at $BLOG_REPO_DIR"

    local original_branch
    original_branch=$(git -C "$BLOG_REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

    # Safety: refuse if docs/projects/flux-infra has uncommitted changes
    local dirty
    dirty=$(git -C "$BLOG_REPO_DIR" status --short -- 'docs/projects/flux-infra/' 'mkdocs.yml' 2>/dev/null || true)
    if [[ -n "$dirty" ]]; then
        echo_error "Blog repo has uncommitted changes in docs/projects/flux-infra/ or mkdocs.yml:"
        echo "$dirty"
        echo_error "Commit or stash those first, then re-run."
        exit 1
    fi

    local branch_name="docs-sync/${TODAY}"
    # Duplicate guard
    if git -C "$BLOG_REPO_DIR" rev-parse --verify "origin/${branch_name}" &>/dev/null; then
        echo_warn "Branch '$branch_name' already exists on origin."
        echo_warn "Check: https://github.com/${BLOG_REPO_GH}/pulls"
        echo_warn "To force a new sync, delete the remote branch first:"
        echo_warn "  gh api -X DELETE repos/${BLOG_REPO_GH}/git/refs/heads/${branch_name}"
        exit 1
    fi

    echo_step "Fetching latest from origin and creating branch"
    git -C "$BLOG_REPO_DIR" fetch origin --quiet
    git -C "$BLOG_REPO_DIR" checkout -b "$branch_name" "origin/main" --quiet

    # Copy generated files into the blog repo
    echo_step "Copying generated files into blog repo"

    # Component pages already written directly into BLOG_REPO_DIR during generation
    # Watermark already written into BLOG_REPO_DIR during advance_watermark
    # mkdocs.yml already patched

    # Stage all changes under docs/projects/flux-infra/ and mkdocs.yml
    git -C "$BLOG_REPO_DIR" add \
        "docs/projects/flux-infra/" \
        "mkdocs.yml"

    # Check if there's actually something to commit
    local staged
    staged=$(git -C "$BLOG_REPO_DIR" diff --cached --name-only)
    if [[ -z "$staged" ]]; then
        echo_info "No changes to commit — docs are already up to date."
        git -C "$BLOG_REPO_DIR" checkout "$original_branch" --quiet 2>/dev/null || true
        exit 0
    fi

    echo_info "Files changed:"
    while IFS= read -r f; do echo "  $f"; done <<< "$staged"

    # Build commit message
    local svc_list
    svc_list=$(printf '%s\n' "${affected_services[@]}" | sort | sed 's/^/  - /')

    git -C "$BLOG_REPO_DIR" commit -m "docs(fleet-infra): sync component docs via update-docs.sh

Affected services:
${svc_list}

Mode: ${MODE}
Source: fleet-infra $(git rev-parse HEAD)
Synced at: ${TODAY}" --quiet

    echo_step "Pushing branch"
    git -C "$BLOG_REPO_DIR" push origin "$branch_name" --quiet

    echo_step "Opening PR"
    gh pr create \
        --repo "$BLOG_REPO_GH" \
        --base main \
        --head "$branch_name" \
        --title "[docs-sync] fleet-infra component docs ${TODAY}" \
        --body "## Documentation sync

**Mode:** ${MODE}
**Source commit:** \`$(git rev-parse HEAD)\` on \`$(git rev-parse --abbrev-ref HEAD)\`

### Services updated

$(printf '%s\n' "${affected_services[@]}" | sort | sed 's/^/- /')

### Changes
- Component pages: created/refreshed
- \`components/index.md\`: layer tables and service count updated
- \`index.md\`: service summary table updated
- \`architecture.md\`: layer subgraphs updated
- \`mkdocs.yml\`: nav updated
- \`.docs-sync-state.json\`: watermark advanced

### Before merging
- [ ] Review each component page for accuracy
- [ ] Verify mermaid diagrams render (\`mkdocs serve\`)
- [ ] Check \`mkdocs build --strict\` passes" \
        --label "docs-sync" 2>/dev/null || \
    gh pr create \
        --repo "$BLOG_REPO_GH" \
        --base main \
        --head "$branch_name" \
        --title "[docs-sync] fleet-infra component docs ${TODAY}" \
        --body "Docs sync from fleet-infra $(git rev-parse HEAD). Mode: ${MODE}. Review before merging."

    echo_step "Restoring blog repo to branch: $original_branch"
    git -C "$BLOG_REPO_DIR" checkout "$original_branch" --quiet 2>/dev/null || true
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo_info "=== update-docs.sh: sync fleet-infra docs to jiwool0920.github.io ==="
    echo_info "Mode: ${MODE}"
    echo ""

    check_prerequisites

    # Read watermark (may upgrade MODE to "all" if no watermark found)
    local watermark
    watermark=$(read_watermark)

    # Enumerate all currently-enabled services
    local all_services_str
    all_services_str=$(enumerate_services)
    local total_enabled
    total_enabled=$(echo "$all_services_str" | grep -c '[a-z]' || true)
    echo_info "Enabled services: ${total_enabled}"

    # Compute affected set (populates global AFFECTED_SERVICES)
    compute_affected "$watermark" "$all_services_str"

    if [[ ${#AFFECTED_SERVICES[@]} -eq 0 && "$MODE" != "all" ]]; then
        echo_info "No infra changes since watermark — docs are up to date."
        echo_info "Run 'make update-docs MODE=all' to force a full reconcile."
        exit 0
    fi

    echo_info "Services to document: ${#AFFECTED_SERVICES[@]}"
    for s in "${AFFECTED_SERVICES[@]}"; do echo "  - $s"; done
    echo ""

    # Drift report: pages without an enabled service (not auto-deleted — just listed)
    echo_step "Drift report"
    while IFS= read -r -d '' page; do
        local pname
        pname=$(basename "$page" .md)
        [[ "$pname" == "index" ]] && continue
        # Check if any enabled service maps to this slug
        local has_service=false
        while IFS= read -r svc; do
            [[ -z "$svc" ]] && continue
            local slug
            slug=$(service_to_slug "$svc")
            if [[ "$slug" == "$pname" ]]; then
                has_service=true
                break
            fi
        done <<< "$all_services_str"
        if [[ "$has_service" == "false" ]]; then
            echo_warn "  Orphan page (no matching enabled service): components/${pname}.md"
        fi
    done < <(find "$COMPONENTS_DIR" -name "*.md" -print0)

    # ── Generate component pages ──────────────────────────────────────────────
    echo ""
    echo_step "Generating component pages"

    local generated_slugs=()
    for svc in "${AFFECTED_SERVICES[@]}"; do
        is_no_standalone_page "$svc" && continue

        local slug
        slug=$(service_to_slug "$svc")

        # Skip if we already generated this slug (multiple services share one page)
        if [[ " ${generated_slugs[*]} " =~ [[:space:]]${slug}[[:space:]] ]]; then
            echo_info "  $svc -> $slug (already generated — sharing page)"
            continue
        fi

        local page_path="${COMPONENTS_DIR}/${slug}.md"
        generate_component_page "$svc" "$page_path"
        generated_slugs+=("$slug")
    done

    # ── Roll-up regeneration (always) ─────────────────────────────────────────
    echo ""
    generate_rollup_pages "$all_services_str"

    # ── Advance watermark ──────────────────────────────────────────────────────
    advance_watermark

    # ── Create PR ─────────────────────────────────────────────────────────────
    echo ""
    create_pr "${AFFECTED_SERVICES[@]}"

    echo ""
    echo_info "Done. PR opened at: https://github.com/${BLOG_REPO_GH}/pulls"
    echo_info "Review, edit, and merge when ready."
    echo ""
}

main "$@"
