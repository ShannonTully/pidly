#!/bin/sh
# Tests for `pidly agents`: the block must be installable, updatable in place,
# and must never damage what a human wrote around it.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/lib.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
count() { c=$(grep -cF "$1" "$2" 2>/dev/null || true); printf '%s' "${c:-0}"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
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
sedi 's|^Work lives in.*|STALE|' AGENTS.md
$PIDLY agents >/dev/null
check "stale block content is replaced" "$(count STALE AGENTS.md)" "0"
check "the current block is present" "$(count 'Work lives in' AGENTS.md)" "1"
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
$PIDLY agents -f >/dev/null 2>&1 && rc=0 || rc=$?
check "-f without a filename is rejected" "$rc" "1"

echo "the shipped reference"
check "README.md is written into .pidly" "$([ -f .pidly/README.md ] && echo yes)" "yes"
check "the block points at it" "$(count '.pidly/README.md' CLAUDE.md)" "1"
for topic in "State is location" "cannot close while it has children" \
             "Never delete a ticket" "cascades upward" "unverifiable" \
             "highest number anywhere in the tracker plus one"; do
	if [ "$(count "$topic" .pidly/README.md)" -ge 1 ]
	then ok "reference covers: $topic"
	else no "reference does not mention: $topic"; fi
done
before=$(cat .pidly/README.md)
$PIDLY agents >/dev/null
check "regenerating leaves it byte-identical" "$(cat .pidly/README.md)" "$before"
printf 'clobbered\n' > .pidly/README.md
$PIDLY agents >/dev/null
check "and a damaged copy is restored" "$(count 'State is location' .pidly/README.md)" "1"

echo "content"
check "the block explains state is location" "$(count 'State is location' CLAUDE.md)" "1"
check "it documents the lease path for cloud agents" "$(count 'PIDLY_LEASE' CLAUDE.md)" "1"
check "it tells agents not to delete tickets" "$(count 'Never delete a ticket' CLAUDE.md)" "1"
lines=$(awk '/pidly:begin/,/pidly:end/' CLAUDE.md | wc -l)
if [ "$lines" -le 40 ]; then ok "the block stays small ($lines lines)"
else no "the block has grown to $lines lines; move detail to .pidly/README.md"; fi

# Both documents once published PIDLY_AGENT=$SESSION_ID, and SESSION_ID is set
# by nothing: it expanded to empty and the claim silently became a pid claim.
# A published agent name must be a name the reader replaces, not a variable
# they are invited to believe in.
bad=0
for f in CLAUDE.md .pidly/README.md; do
	if grep -q 'PIDLY_AGENT=\$' "$f"; then
		no "$f tells the reader to claim with a shell variable"
		bad=1
	fi
done
[ "$bad" -eq 0 ] && ok "neither document claims with a \$variable"

# Both once said `PIDLY_PID=$$ pidly claim 7`. $$ is the shell running the
# command, and a harness that gives each command a fresh shell ends it when
# the call returns, so the claim read dead at once (ticket 76). A line may
# still name the idiom to warn against it.
bad=0
for f in CLAUDE.md .pidly/README.md; do
	if grep -F 'PIDLY_PID=$$' "$f" | grep -Evq "Don't|Never"; then
		no "$f tells the reader to claim with PIDLY_PID=\$\$"
		bad=1
	fi
done
[ "$bad" -eq 0 ] && ok "neither document claims with PIDLY_PID=\$\$"
check "the block claims with plain pidly claim" \
	"$(grep -c '^pidly claim 7 ' CLAUDE.md)" "1"
check "the reference warns against PIDLY_PID=\$\$" \
	"$(grep -cF "Don't prefix a claim with \`PIDLY_PID=\$\$\`" .pidly/README.md)" "1"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
