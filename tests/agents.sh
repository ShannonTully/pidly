#!/bin/sh
# Tests for `pidly agents`: the block must be installable, updatable in place,
# and must never damage what a human wrote around it.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
count() { c=$(grep -cF "$1" "$2" 2>/dev/null || true); printf '%s' "${c:-0}"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"; mkdir -p .pidly

echo "installing"
$PIDLY agents >/dev/null
check "creates AGENTS.md when none exists" "$([ -f AGENTS.md ] && echo yes)" "yes"
check "writes one begin marker" "$(count '<!-- pidly:begin -->' AGENTS.md)" "1"
check "writes one end marker" "$(count '<!-- pidly:end -->' AGENTS.md)" "1"

echo "idempotency"
$PIDLY agents >/dev/null
check "a second run does not duplicate the block" "$(count '<!-- pidly:begin -->' AGENTS.md)" "1"
before=$(cat AGENTS.md)
$PIDLY agents >/dev/null
check "and leaves the file byte-identical" "$(cat AGENTS.md)" "$before"

echo "surrounding content"
rm AGENTS.md
printf '# Project\n\nKEEP BEFORE\n' > AGENTS.md
$PIDLY agents >/dev/null
printf '\n## After\n\nKEEP AFTER\n' >> AGENTS.md
sed -i 's|^Work is tracked in.*|STALE|' AGENTS.md
$PIDLY agents >/dev/null
check "stale block content is replaced" "$(count STALE AGENTS.md)" "0"
check "the current block is present" "$(count 'Work is tracked in' AGENTS.md)" "1"
check "text before the block survives" "$(count 'KEEP BEFORE' AGENTS.md)" "1"
check "text after the block survives" "$(count 'KEEP AFTER' AGENTS.md)" "1"
check "still exactly one block" "$(count '<!-- pidly:begin -->' AGENTS.md)" "1"

echo "file selection"
rm -f AGENTS.md
printf '# c\n' > CLAUDE.md
$PIDLY agents >/dev/null
check "uses an existing CLAUDE.md" "$(count '<!-- pidly:begin -->' CLAUDE.md)" "1"
check "and does not create AGENTS.md" "$([ -f AGENTS.md ] && echo yes || echo no)" "no"
$PIDLY agents -f custom.md >/dev/null
check "-f targets an explicit file" "$(count '<!-- pidly:begin -->' custom.md)" "1"
out=$($PIDLY agents -f 2>&1) && rc=0 || rc=$?
check "-f without a filename is rejected" "$rc" "1"

echo "content"
check "the block explains state is location" "$(count 'State is location' CLAUDE.md)" "1"
check "it documents the lease path for cloud agents" "$(count 'PIDLY_LEASE' CLAUDE.md)" "1"
check "it tells agents not to delete tickets" "$(count 'Never delete a ticket' CLAUDE.md)" "1"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
