#!/usr/bin/env bash

# Checks that infra changes (apps/base/<svc>/ or base/services/<svc>.yaml)
# are accompanied by at least one doc update (README.md, docs/adr/, or CLAUDE.md).
# Runs as a pre-push hook so it doesn't nag on every small commit.

set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}INFO${NC} - $1"; }
echo_error() { echo -e "${RED}ERROR${NC} - $1"; }

# Collect all files changed since origin/HEAD (the commits being pushed)
# When running as pre-push, git provides remote/local SHA pairs on stdin.
# We fall back to diff against the tracking branch if stdin is empty.
get_changed_files() {
    local changed_files=""

    # pre-push hook receives lines: <local_ref> <local_sha> <remote_ref> <remote_sha>
    while read -r _local_ref local_sha _remote_ref remote_sha; do
        if [[ "$remote_sha" == "0000000000000000000000000000000000000000" ]]; then
            # New branch being pushed — compare against default branch
            local base
            base=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo "origin/main")
            changed_files+=$(git diff --name-only "${base}" "${local_sha}" 2>/dev/null)
        else
            changed_files+=$(git diff --name-only "${remote_sha}" "${local_sha}" 2>/dev/null)
        fi
        changed_files+=$'\n'
    done

    # Fallback: nothing piped (e.g. manual invocation)
    if [[ -z "${changed_files// }" ]]; then
        changed_files=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || git diff --name-only HEAD 2>/dev/null || true)
    fi

    echo "$changed_files"
}

main() {
    echo_info "Checking documentation freshness for infra changes"

    local changed_files
    changed_files=$(get_changed_files)

    # Detect doc files touched in this push
    local docs_changed=false
    if echo "$changed_files" | grep -qE '^(README\.md|CLAUDE\.md|docs/adr/|docs/)'; then
        docs_changed=true
    fi

    # Extract unique service names from changed infra paths
    local -a services_changed=()

    # Pattern 1: apps/base/<svc>/... -> extract <svc>
    while IFS= read -r file; do
        if [[ "$file" =~ ^apps/base/([^/]+)/ ]]; then
            local svc="${BASH_REMATCH[1]}"
            # Avoid duplicates
            if [[ ! " ${services_changed[*]} " =~ ${svc} ]]; then
                services_changed+=("$svc")
            fi
        fi
    done < <(echo "$changed_files")

    # Pattern 2: base/services/<svc>.yaml -> extract <svc>
    while IFS= read -r file; do
        if [[ "$file" =~ ^base/services/([^/]+)\.ya?ml$ ]]; then
            local svc="${BASH_REMATCH[1]}"
            if [[ ! " ${services_changed[*]} " =~ ${svc} ]]; then
                services_changed+=("$svc")
            fi
        fi
    done < <(echo "$changed_files")

    if [[ ${#services_changed[@]} -eq 0 ]]; then
        echo_info "No infra service changes detected — skipping doc freshness check"
        exit 0
    fi

    echo_info "Infra changes detected for: ${services_changed[*]}"

    if $docs_changed; then
        echo_info "Documentation update found — freshness requirement satisfied"
        echo_info "Changed services: ${services_changed[*]}"
        exit 0
    fi

    # Docs not updated
    echo ""
    echo_error "Infra changes without documentation update"
    echo ""
    echo "  Changed services:"
    for svc in "${services_changed[@]}"; do
        echo "    - ${svc}"
    done
    echo ""
    echo "  Expected: at least one of these to be updated:"
    echo "    README.md"
    echo "    CLAUDE.md"
    echo "    docs/adr/<new-or-updated>.md"
    echo ""
    echo "  Options:"
    echo "    1. Update docs manually, then push again"
    echo "    2. Run 'make docs-draft' to get an AI-drafted update"
    echo "    3. Skip (only if change is truly trivial):"
    echo "       SKIP=docs-freshness git push"
    echo ""
    exit 1
}

main "$@"
