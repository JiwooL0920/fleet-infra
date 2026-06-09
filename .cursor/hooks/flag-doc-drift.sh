#!/usr/bin/env bash

# Advisory hook: fires after Cursor edits a service file under apps/base/ or base/services/.
# Emits a non-blocking reminder so doc updates are not forgotten mid-session.
# Does NOT fail (no exit 1) — this is informational only.

INPUT=$(cat)
EDITED_FILE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('path',''))" 2>/dev/null || echo "")

if [[ -z "$EDITED_FILE" ]]; then
    exit 0
fi

# Extract service name from path
SERVICE=""
if [[ "$EDITED_FILE" =~ apps/base/([^/]+)/ ]]; then
    SERVICE="${BASH_REMATCH[1]}"
elif [[ "$EDITED_FILE" =~ base/services/([^/]+)\.ya?ml$ ]]; then
    SERVICE="${BASH_REMATCH[1]}"
fi

if [[ -z "$SERVICE" ]]; then
    exit 0
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE=".cursor/doc-drift.log"

# Append to drift log (read by session summary / make docs-draft)
echo "[${TIMESTAMP}] Service '${SERVICE}' modified (${EDITED_FILE}) — docs may need update" >> "${LOG_FILE}" 2>/dev/null || true

# Emit advisory notice to Cursor via stdout (JSON response)
cat <<EOF
{
  "type": "notice",
  "message": "Doc reminder: '${SERVICE}' was modified. Update README.md, docs/adr/, or CLAUDE.md before pushing. Run 'make docs-draft' for AI-drafted suggestions."
}
EOF
