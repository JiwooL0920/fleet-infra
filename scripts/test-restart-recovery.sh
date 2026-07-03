#!/usr/bin/env bash
set -euo pipefail

if [[ "${DEBUG:-0}" == "1" ]]; then
  set -x
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Repo root
REPO_ROOT="$(git rev-parse --show-toplevel)"
EVIDENCE_DIR="${REPO_ROOT}/.sisyphus/evidence"

# Ensure evidence directory exists
mkdir -p "$EVIDENCE_DIR"

# Timestamp for log file
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${EVIDENCE_DIR}/restart-test-${TIMESTAMP}.log"

# Flags
DRY_RUN=true
TIMEOUT_SECONDS=600  # 10 minutes

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      DRY_RUN=false
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--yes]"
      exit 1
      ;;
  esac
done

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
  echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_FILE"
}

log_success() {
  echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
  echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}❌ $*${NC}" | tee -a "$LOG_FILE"
}

# Check cluster health by examining kustomizations
check_health() {
  log_info "Checking cluster health..."

  local unhealthy=()
  local output

  output=$(flux get kustomizations -A 2>/dev/null || echo "")

  if [[ -z "$output" ]]; then
    log_error "Failed to get kustomizations — is Flux running?"
    return 1
  fi

  # Parse output, skip header, skip ollama and SUSPENDED entries
  # Format: NAMESPACE NAME REVISION SUSPENDED READY MESSAGE
  while IFS=$'\t' read -r namespace name _ suspended ready _; do
    # Trim whitespace from fields
    namespace="${namespace// /}"
    name="${name// /}"
    suspended="${suspended// /}"
    ready="${ready// /}"

    # Skip empty lines and header
    [[ -z "$namespace" ]] && continue
    [[ "$namespace" == "NAMESPACE" ]] && continue

    # Skip ollama (intentionally suspended)
    [[ "$name" == "ollama" ]] && continue

    # Skip if SUSPENDED is True
    [[ "$suspended" == "True" ]] && continue

    # Check if READY is not "True"
    if [[ "$ready" != "True" ]]; then
      unhealthy+=("$namespace/$name (ready: $ready)")
    fi
  done <<< "$output"

  if [[ ${#unhealthy[@]} -gt 0 ]]; then
    log_error "Found ${#unhealthy[@]} unhealthy kustomization(s):"
    for item in "${unhealthy[@]}"; do
      echo "  - $item" | tee -a "$LOG_FILE"
    done
    return 1
  fi

  log_success "All kustomizations are healthy (ollama intentionally suspended)"
  return 0
}

# Wait for all kustomizations to be Ready (except ollama and suspended)
wait_for_flux() {
  log_info "Waiting for Flux reconciliation (timeout: ${TIMEOUT_SECONDS}s)..."

  local elapsed=0
  local interval=15
  local max_attempts=$((TIMEOUT_SECONDS / interval))
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    if check_health; then
      log_success "Flux reconciliation complete!"
      return 0
    fi

    attempt=$((attempt + 1))
    elapsed=$((attempt * interval))

    if [[ $attempt -lt $max_attempts ]]; then
      log_info "Waiting... ($elapsed/${TIMEOUT_SECONDS}s) [attempt $attempt/$max_attempts]"
      sleep "$interval"
    fi
  done

  log_error "Timeout waiting for Flux reconciliation after ${TIMEOUT_SECONDS}s"
  return 1
}

# Generate report
report() {
  local status="$1"

  echo "" | tee -a "$LOG_FILE"
  echo "═══════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"

  if [[ "$status" == "PASS" ]]; then
    log_success "Restart recovery test PASSED"
    echo "═══════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    log_info "Evidence saved to: $LOG_FILE"
    return 0
  else
    log_error "Restart recovery test FAILED"
    echo "═══════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    log_info "Evidence saved to: $LOG_FILE"
    return 1
  fi
}

# ============================================================================
# Main Logic
# ============================================================================

echo "" | tee -a "$LOG_FILE"
echo "═══════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
log_info "Cluster Restart Recovery Test"
echo "═══════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "Running in read-only mode (no cluster changes)"
  echo "" | tee -a "$LOG_FILE"

  if check_health; then
    report "PASS"
    exit 0
  else
    report "FAIL"
    exit 1
  fi
else
  # --yes mode: perform colima restart
  log_warning "This will run: colima stop && sleep 10 && colima start"
  log_warning "Press Ctrl-C within 5 seconds to cancel..."
  echo "" | tee -a "$LOG_FILE"

  sleep 5

  echo "" | tee -a "$LOG_FILE"
  log_info "Starting colima restart sequence..."
  echo "" | tee -a "$LOG_FILE"

  log_info "Stopping colima..."
  if colima stop 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Colima stopped"
  else
    log_error "Failed to stop colima"
    report "FAIL"
    exit 1
  fi

  echo "" | tee -a "$LOG_FILE"
  log_info "Waiting 10 seconds before restart..."
  sleep 10

  echo "" | tee -a "$LOG_FILE"
  log_info "Starting colima..."
  if colima start 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Colima started"
  else
    log_error "Failed to start colima"
    report "FAIL"
    exit 1
  fi

  echo "" | tee -a "$LOG_FILE"
  log_info "Waiting for cluster to stabilize..."
  sleep 10

  echo "" | tee -a "$LOG_FILE"
  if wait_for_flux; then
    report "PASS"
    exit 0
  else
    report "FAIL"
    exit 1
  fi
fi
