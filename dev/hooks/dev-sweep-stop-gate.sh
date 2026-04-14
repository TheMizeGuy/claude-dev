#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
# SESSION_DIR passed as env var by the orchestrator at registration time.
# Fallback to repo-derived path if env var missing (e.g., manual hook test).
SESSION_DIR="${DEV_SESSION_DIR:-$PROJECT_ROOT/.claude/dev-sessions/$SESSION_ID}"
ACTIVE_MARKER="$SESSION_DIR/active"
DONE_MARKER="$SESSION_DIR/done"
STATE_FILE="$SESSION_DIR/session-state.json"

# Only gate if this session activated the dev sweep
[[ -f "$ACTIVE_MARKER" ]] || exit 0

# Check if sweep explicitly completed
if [[ -f "$DONE_MARKER" ]]; then
  rm -f "$ACTIVE_MARKER"
  exit 0
fi

# TTL safety: activity-based, not wall-clock from creation.
# The team lead touches $ACTIVE_MARKER after every state transition (dispatch,
# return, merge, review). If $ACTIVE_MARKER mtime is older than TTL, the sweep
# is either finished or the team lead crashed — release.
# Default TTL: 1 hour of INACTIVITY (not total duration). 15-wave sweeps are
# fine as long as the lead is actively progressing.
if [[ -f "$ACTIVE_MARKER" ]]; then
  TTL_HOURS="${DEV_STOP_HOOK_INACTIVITY_TTL_HOURS:-1}"
  TTL_SECONDS=$((TTL_HOURS * 3600))
  # Portable: try GNU stat, fall back to BSD stat
  MTIME=$(stat -c %Y "$ACTIVE_MARKER" 2>/dev/null || stat -f %m "$ACTIVE_MARKER" 2>/dev/null || echo 0)
  AGE=$(( $(date +%s) - MTIME ))
  if [[ $AGE -gt $TTL_SECONDS ]]; then
    rm -f "$ACTIVE_MARKER"
    exit 0
  fi
fi

if [[ ! -f "$STATE_FILE" ]]; then
  cat <<EOF
{"decision":"block","reason":"DEV SWEEP: session-state.json missing but active marker exists. Resume with /dev or clean up with: rm $ACTIVE_MARKER"}
EOF
  exit 0
fi

# Read state. On parse/runtime failure: BLOCK (fail-closed) with diagnostic message.
# Rationale: fail-open silently releases the gate on tooling failures. Fail-closed
# forces the user to investigate. The user can always `touch $DONE_MARKER` to release.
PARSE_OK=true
TOTAL=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(len(d.get('stories',{})))" 2>/dev/null) || PARSE_OK=false
DONE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(sum(1 for s in d.get('stories',{}).values() if s.get('state')=='Done'))" 2>/dev/null) || PARSE_OK=false
BLOCKED=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(sum(1 for s in d.get('stories',{}).values() if s.get('state')=='Blocked'))" 2>/dev/null) || PARSE_OK=false

if [[ "$PARSE_OK" != "true" ]]; then
  cat <<EOF
{"decision":"block","reason":"DEV SWEEP: Failed to parse session-state.json. File may be corrupt or python3 missing. Investigate: $STATE_FILE. Release: touch $DONE_MARKER"}
EOF
  exit 0
fi

REMAINING=$((TOTAL - DONE - BLOCKED))

if [[ $REMAINING -le 0 ]]; then
  rm -f "$ACTIVE_MARKER"
  exit 0
fi

cat <<EOF
{"decision":"block","reason":"DEV SWEEP: $DONE/$TOTAL done, $BLOCKED blocked, $REMAINING remaining. Continue working. Abort: touch $DONE_MARKER"}
EOF
exit 0
