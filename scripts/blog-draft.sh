#!/usr/bin/env bash

# Generates a blog post draft from recent fleet-infra commits using local opencode,
# then creates a branch in jiwool0920.github.io and opens a GitHub PR.
#
# Usage:
#   scripts/blog-draft.sh [RANGE]
#
#   RANGE  git log/diff range (default: HEAD~1..HEAD)
#          Examples:
#            HEAD~3..HEAD        last three commits
#            develop~5..develop  five commits on develop
#
# Prerequisites:
#   - opencode installed and authenticated (uses your existing opencode.jsonc config)
#   - gh installed and authenticated (gh auth status must show JiwooL0920)
#   - Blog repo cloned at $BLOG_REPO_DIR (default: ~/Project/jiwool0920.github.io)
#
# Environment:
#   BLOG_REPO_DIR   Path to local blog clone (default: ~/Project/jiwool0920.github.io)
#   BLOG_REPO_GH    GitHub repo slug for PR creation (default: JiwooL0920/jiwool0920.github.io)
#   BLOG_DRAFT_MODEL  opencode model string; leave unset to use your opencode.jsonc default

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
RANGE="${1:-HEAD~1..HEAD}"
BLOG_REPO_DIR="${BLOG_REPO_DIR:-${HOME}/Project/jiwool0920.github.io}"
BLOG_REPO_GH="${BLOG_REPO_GH:-JiwooL0920/jiwool0920.github.io}"
TODAY="$(date '+%Y-%m-%d')"

PROMPT_FILE="$(mktemp /tmp/blog-prompt-XXXX.txt)"
OUTPUT_FILE="$(mktemp /tmp/blog-draft-XXXX.md)"
ERR_FILE="/tmp/blog-opencode-err.txt"

cleanup() {
    rm -f "$PROMPT_FILE" "$OUTPUT_FILE"
}
trap cleanup EXIT

# ── Prerequisites check ────────────────────────────────────────────────────────
check_prerequisites() {
    local missing=()

    command -v opencode &>/dev/null || missing+=("opencode")
    command -v gh       &>/dev/null || missing+=("gh")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo_error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    if [[ ! -d "$BLOG_REPO_DIR" ]]; then
        echo_error "Blog repo not found at: $BLOG_REPO_DIR"
        echo_error "Set BLOG_REPO_DIR to your local clone of jiwool0920.github.io"
        exit 1
    fi

    # Verify gh is authenticated
    if ! gh auth status &>/dev/null; then
        echo_error "gh is not authenticated. Run: gh auth login"
        exit 1
    fi
}

# ── Collect diff context ───────────────────────────────────────────────────────
collect_context() {
    echo_step "Collecting git context for range: $RANGE"

    # Commit log
    local log
    log=$(git log "$RANGE" --format="- %s (%h)" 2>/dev/null | head -20 || true)

    if [[ -z "$log" ]]; then
        echo_warn "No commits found in range '$RANGE'. Falling back to HEAD~1..HEAD"
        RANGE="HEAD~1..HEAD"
        log=$(git log "$RANGE" --format="- %s (%h)" 2>/dev/null | head -20 || true)
    fi

    # Diff filtered to infra paths (capped at 10KB to avoid token overflow)
    local diff
    diff=$(git diff "$RANGE" -- 'apps/base/' 'base/services/' 'docs/adr/' 2>/dev/null \
           | head -c 10240 || true)

    # Derive slug from latest commit subject
    local subject
    subject=$(git log -1 --format="%s" 2>/dev/null || echo "infra-update")
    # lowercase, replace non-alphanumeric runs with dashes, trim edges
    local slug
    slug=$(echo "$subject" \
           | tr '[:upper:]' '[:lower:]' \
           | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' \
           | cut -c1-50)
    slug="${slug:-infra-update}"

    BRANCH_NAME="blog-draft/${TODAY}-${slug}"
    POST_FILENAME="${TODAY}-${slug}.md"

    echo_info "Slug: $slug"
    echo_info "Branch: $BRANCH_NAME"
    echo_info "Post file: $POST_FILENAME"

    # Write prompt + context into a single file for opencode -f attachment
    cat > "$PROMPT_FILE" <<PROMPT
CRITICAL INSTRUCTION: Output ONLY the raw Markdown blog post. Your very first character must be
the hyphen of the opening YAML frontmatter (---). Do NOT write any narration, reasoning,
"I detect...", tool calls, research steps, or explanation. Do NOT use any tools. All context
needed is provided in this file. Start your response with --- immediately.

---

You are writing a technical blog post for a MkDocs Material site at https://jiwool0920.github.io.
Author: Jiwoo Lee, platform engineer. Style: direct, practical, no marketing language.

## Commits in this push

${log}

## Git diff (filtered to apps/base/, base/services/, docs/adr/ — may be truncated)

${diff}

---

Write a complete blog post in Markdown. Use EXACTLY this frontmatter structure:

---
date: ${TODAY}
categories:
  - Infrastructure
  - <one additional relevant category>
tags:
  - <3-5 relevant lowercase tags separated by newlines with leading dashes>
authors:
  - jiwoo
---

Then write a 2-3 sentence introductory paragraph, followed by a <!-- more --> fold on its own line.

Include these sections (use ## headings):
- Overview
- Why This Change
- Technical Details
- Operational Impact

Use mermaid code blocks where an architecture or flow diagram adds clarity (fence with \`\`\`mermaid ... \`\`\`).
Target audience: platform/DevOps engineers.
Output ONLY the Markdown file body — no preamble, no explanation outside the post itself.
PROMPT

    echo_info "Context written to prompt file ($(wc -c < "$PROMPT_FILE") bytes)"
}

# ── Fast-fail duplicate-branch guard ──────────────────────────────────────────
# Called BEFORE generate_draft so we don't waste 90s on opencode if the PR
# for this commit range was already opened.
check_branch_guard() {
    git -C "$BLOG_REPO_DIR" fetch origin --quiet 2>/dev/null || true
    if git -C "$BLOG_REPO_DIR" rev-parse --verify "origin/${BRANCH_NAME}" &>/dev/null; then
        local existing_pr
        existing_pr=$(gh pr list --repo "$BLOG_REPO_GH" \
            --head "$BRANCH_NAME" --json url --jq '.[0].url' 2>/dev/null || true)
        echo_warn "Branch '$BRANCH_NAME' already exists — draft was already created."
        if [[ -n "$existing_pr" ]]; then
            echo_info "Existing PR: $existing_pr"
        else
            echo_warn "Check open PRs: https://github.com/${BLOG_REPO_GH}/pulls"
        fi
        echo_warn "To regenerate, delete the remote branch first:"
        echo_warn "  gh api -X DELETE repos/${BLOG_REPO_GH}/git/refs/heads/${BRANCH_NAME}"
        exit 0
    fi
}

# ── Generate draft with opencode ───────────────────────────────────────────────
generate_draft() {
    echo_step "Generating blog post draft with opencode..."
    echo_info "This may take 30-90 seconds depending on your model"

    local model_flag=()
    if [[ -n "${BLOG_DRAFT_MODEL:-}" ]]; then
        model_flag=(-m "$BLOG_DRAFT_MODEL")
    fi

    # Key fixes for non-interactive use:
    #   < /dev/null        — prevents opencode blocking on the 'question' tool
    #   --dangerously-skip-permissions — auto-approves the file-read permission prompt
    #   > $OUTPUT_FILE     — capture stdout (the generated post)
    #   2>$ERR_FILE        — capture stderr separately so it doesn't pollute the post
    if ! opencode run \
            "Output ONLY the Markdown blog post from the attached file. Start your response with --- (YAML frontmatter). No narration, no tool calls, no research." \
            -f "$PROMPT_FILE" \
            "${model_flag[@]}" \
            --dangerously-skip-permissions \
            < /dev/null \
            > "$OUTPUT_FILE" \
            2>"$ERR_FILE"; then
        echo_error "opencode exited with a non-zero status"
        echo_error "stderr output:"
        cat "$ERR_FILE" >&2
        exit 1
    fi

    # Strip ANSI escape codes opencode may emit even in non-interactive mode
    sed -i '' 's/\x1b\[[0-9;]*[mGKHF]//g' "$OUTPUT_FILE" 2>/dev/null || \
        sed -i 's/\x1b\[[0-9;]*[mGKHF]//g' "$OUTPUT_FILE" 2>/dev/null || true

    # Strip any preamble text the model emits before the YAML frontmatter.
    # opencode's Sisyphus agent narrates tool calls ("I detect writing intent...")
    # before producing the actual markdown — awk discards everything up to the
    # first line that starts with "---".
    local stripped
    stripped=$(awk '/^---/{found=1} found{print}' "$OUTPUT_FILE")
    if [[ -n "$stripped" ]]; then
        echo "$stripped" > "$OUTPUT_FILE"
    fi

    # Validate: must contain YAML frontmatter
    if ! head -1 "$OUTPUT_FILE" | grep -q '^---'; then
        echo_error "opencode output does not look like a valid blog post (no frontmatter)."
        echo_error "Raw output:"
        cat "$OUTPUT_FILE" >&2
        if [[ -s "$ERR_FILE" ]]; then
            echo_error "stderr:"
            cat "$ERR_FILE" >&2
        fi
        exit 1
    fi

    local line_count
    line_count=$(wc -l < "$OUTPUT_FILE")
    echo_info "Draft generated: ${line_count} lines"
}

# ── Create branch and PR in blog repo ─────────────────────────────────────────
create_pr() {
    echo_step "Preparing blog repo at $BLOG_REPO_DIR"

    local original_branch
    original_branch=$(git -C "$BLOG_REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

    # Safety: refuse if blog/posts has uncommitted changes (would be clobbered by checkout)
    local dirty_posts
    dirty_posts=$(git -C "$BLOG_REPO_DIR" status --short -- 'docs/blog/posts/' 2>/dev/null || true)
    if [[ -n "$dirty_posts" ]]; then
        echo_error "Blog repo has uncommitted changes in docs/blog/posts/:"
        echo "$dirty_posts"
        echo_error "Commit or stash those first, then re-run."
        exit 1
    fi

    echo_step "Fetching latest from origin and creating branch"
    git -C "$BLOG_REPO_DIR" fetch origin --quiet

    git -C "$BLOG_REPO_DIR" checkout -b "$BRANCH_NAME" "origin/main" --quiet

    # Copy the draft
    local dest="${BLOG_REPO_DIR}/docs/blog/posts/${POST_FILENAME}"
    cp "$OUTPUT_FILE" "$dest"
    echo_info "Post written to: $dest"

    # Commit
    git -C "$BLOG_REPO_DIR" add "docs/blog/posts/${POST_FILENAME}"
    git -C "$BLOG_REPO_DIR" commit -m "docs(blog): draft post ${POST_FILENAME}

Auto-drafted from fleet-infra commits (${RANGE}).
Review and edit before merging." --quiet

    echo_step "Pushing branch"
    git -C "$BLOG_REPO_DIR" push origin "$BRANCH_NAME" --quiet

    echo_step "Opening PR"

    # Build PR body with commit context
    local commits_list
    commits_list=$(git log "$RANGE" --format="- %s (%h)" 2>/dev/null | head -10 || echo "- (see diff)")

    gh pr create \
        --repo "$BLOG_REPO_GH" \
        --base main \
        --head "$BRANCH_NAME" \
        --title "[blog-draft] ${POST_FILENAME}" \
        --body "## Auto-drafted blog post

**Source:** fleet-infra commits \`${RANGE}\`

### Commits included
${commits_list}

### Before merging
- [ ] Review and edit the content
- [ ] Verify mermaid diagrams render (run \`mkdocs serve\` locally)
- [ ] Confirm frontmatter tags/categories are accurate
- [ ] MkDocs build passes (\`mkdocs build --strict\`)" \
        --label "blog-draft" 2>/dev/null || \
    gh pr create \
        --repo "$BLOG_REPO_GH" \
        --base main \
        --head "$BRANCH_NAME" \
        --title "[blog-draft] ${POST_FILENAME}" \
        --body "Auto-drafted from fleet-infra ${RANGE}. Review before merging."

    # Restore blog repo to original branch
    echo_step "Restoring blog repo to branch: $original_branch"
    git -C "$BLOG_REPO_DIR" checkout "$original_branch" --quiet 2>/dev/null || true
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo_info "=== blog-draft.sh: draft blog post from fleet-infra commits ==="
    echo ""

    check_prerequisites
    collect_context
    check_branch_guard   # fast-fail before spending 90s on opencode
    generate_draft
    create_pr

    echo ""
    echo_info "Done. PR opened at: https://github.com/${BLOG_REPO_GH}/pulls"
    echo_info "Review, edit, and merge when ready. The blog deploys automatically on merge to main."
    echo ""
}

main "$@"
