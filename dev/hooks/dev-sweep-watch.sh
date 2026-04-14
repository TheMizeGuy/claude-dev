#!/usr/bin/env bash
set -euo pipefail

# Live dashboard for dev plugin sweeps.
# Usage: ./dev-sweep-watch.sh [session-dir]
#
# Run in a separate terminal while /dev is executing. Renders a live table
# of story states, agent dispatch status, and wave progress.
#
# If no session-dir argument: auto-discovers the most recent active session.

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
SESSION_BASE="$PROJECT_ROOT/.claude/dev-sessions"

if [[ $# -ge 1 ]]; then
  SESSION_DIR="$1"
else
  # Auto-discover most recent active session
  SESSION_DIR=""
  for d in "$SESSION_BASE"/*/; do
    [[ -f "$d/active" ]] && SESSION_DIR="$d"
  done
  if [[ -z "$SESSION_DIR" ]]; then
    echo "No active dev session found in $SESSION_BASE"
    echo "Start a sweep with /dev, then re-run this script."
    exit 1
  fi
fi

STATE_FILE="$SESSION_DIR/session-state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Waiting for session-state.json at $STATE_FILE..."
  while [[ ! -f "$STATE_FILE" ]]; do sleep 1; done
fi

render() {
  clear
  local now
  now=$(date '+%H:%M:%S')

  # Parse state with python3 for reliable JSON handling
  python3 -c "
import json, sys, os
from datetime import datetime

try:
    with open('$STATE_FILE') as f:
        state = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    print('Waiting for valid state...')
    sys.exit(0)

stories = state.get('stories', {})
wave = state.get('current_wave', 0)
total_waves = state.get('total_waves', 0)
dispatched = state.get('agents_dispatched', 0)
max_agents = state.get('max_agents_per_session', 0)
integration = state.get('integration_branch', '?')

# Counts
done_count = sum(1 for s in stories.values() if s.get('state') == 'Done')
progress_count = sum(1 for s in stories.values() if s.get('state') == 'In Progress')
blocked_count = sum(1 for s in stories.values() if s.get('state') == 'Blocked')
ready_count = sum(1 for s in stories.values() if s.get('state') == 'Ready')
total = len(stories)

# CI status
ci = state.get('ci', {})
ci_type = ci.get('type', 'none')
ci_status = ci.get('status', 'pending')
ci_url = ci.get('run_url', '')

# Header
print(f'DEV SWEEP DASHBOARD  [{\"$now\"}]')
print(f'Session: {os.path.basename(os.path.dirname(\"$STATE_FILE\"))}')
print(f'Branch:  {integration}')
print(f'Wave:    {wave}/{total_waves}    Agents: {dispatched}/{max_agents}')
if ci_type != 'none':
    ci_label = ci_status.upper()
    ci_extra = f'  {ci_url}' if ci_url else ''
    print(f'CI:      {ci_type} [{ci_label}]{ci_extra}')
print()

# Progress bar
if total > 0:
    pct = int(done_count / total * 40)
    bar = '#' * pct + '-' * (40 - pct)
    print(f'[{bar}] {done_count}/{total} done')
else:
    print('[no stories]')
print()

# Story table
print(f'{\"Story\":<20} {\"State\":<14} {\"Wave\":<6} {\"Skill\":<30} {\"Review\":<10}')
print('-' * 82)
for sid, s in sorted(stories.items(), key=lambda x: (x[1].get('wave', 99), x[0])):
    st = s.get('state', '?')
    w = s.get('wave', '?')
    sk = s.get('skill', '?')[:28]
    rv = s.get('review_status', '-')
    # Color codes
    if st == 'Done':
        tag = '  DONE'
    elif st == 'In Progress':
        tag = '  WORKING'
    elif st == 'Blocked':
        tag = '  BLOCKED'
    else:
        tag = ''
    print(f'{sid:<20} {st:<14} {str(w):<6} {sk:<30} {rv:<10}{tag}')

# Errors
errors = [(sid, s.get('errors', [])) for sid, s in stories.items() if s.get('errors')]
if errors:
    print()
    print('ERRORS:')
    for sid, errs in errors:
        for e in errs:
            print(f'  {sid}: {e}')
"
}

echo "Watching $STATE_FILE (Ctrl-C to stop)"
echo ""

# Initial render
render

# Watch for changes using fswatch if available, otherwise poll
if command -v fswatch >/dev/null 2>&1; then
  fswatch -1 "$STATE_FILE" 2>/dev/null | while read -r _; do
    render
  done
  # fswatch -1 exits after first event, loop it
  while true; do
    fswatch -1 "$STATE_FILE" 2>/dev/null
    render
  done
else
  while true; do
    sleep 2
    render
  done
fi
