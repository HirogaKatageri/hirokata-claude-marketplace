#!/bin/bash
# Board benchmark: runs one guild flow headless on a seeded scratch project, then checks it.
# Usage: run.sh <scenario> <out-dir> [run-number]
#   scenarios: approvals | execute | shift
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$(cd "$HERE/../.." && pwd)"
SC="$1"; OUT="$2"; N="${3:-1}"
DIR="$OUT/$SC-$N"; rm -rf "$DIR"; mkdir -p "$DIR/project"
case "$SC" in
  approvals) SEEDS="seed-common.sql seed-admin.sql"; TURNS=40; BUDGET=4
    PROMPT="let's get to work on the guild board" ;;
  execute)   SEEDS="seed-common.sql seed-approved.sql"; TURNS=200; BUDGET=20
    PROMPT="let's get to work on the guild board" ;;
  shift)     SEEDS="seed-common.sql seed-admin.sql"; TURNS=250; BUDGET=25
    PROMPT="Work a shift on the guild board while I'm away. Budget: 10 plans and 45 minutes. Nobody will be here to answer questions." ;;
  *) echo "unknown scenario $SC"; exit 2 ;;
esac
( cd "$HERE" && cat $SEEDS ) > "$DIR/seed.sql"
( cd "$DIR/project" && "$HERE/fixture.sh" "$DIR/seed.sql" ) || { echo "fixture failed"; exit 2; }
start=$(date +%s)
( cd "$DIR/project" && timeout 3600 claude -p "$PROMPT" \
    --plugin-dir "$PLUGIN" --add-dir "$PLUGIN" --add-dir /tmp --permission-mode acceptEdits \
    --allowedTools Bash Read Write Edit Glob Grep Skill Agent AskUserQuestion SendMessage TodoWrite \
    --max-turns "$TURNS" --max-budget-usd "$BUDGET" --no-session-persistence \
    --output-format stream-json --verbose ) > "$DIR/stream.jsonl" 2> "$DIR/stderr.log"
echo "exit=$? seconds=$(( $(date +%s) - start ))" > "$DIR/run.txt"
python3 "$HERE/check.py" "$SC" "$DIR" | tee "$DIR/score.txt"
