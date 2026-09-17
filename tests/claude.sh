#!/bin/sh
# Tests for `pidly claude`: the files it writes into .claude, and what check
# says when one of them drifts.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/lib.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF "$3"; then no "$1 (unexpected '$3')"; else ok "$1"; fi; }
count() { grep -cF "$1" "$2" 2>/dev/null || true; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null

echo "what it writes"
out=$($PIDLY claude)
check "the skill" "$([ -f .claude/skills/pidly/SKILL.md ] && echo yes)" "yes"
for c in next mine drop; do
	check "the /pidly-$c command" \
		"$([ -f ".claude/commands/pidly-$c.md" ] && echo yes)" "yes"
done
check "and it says so" "$(printf '%s' "$out" | grep -c '^wrote ')" "5"

echo "the skill itself"
check "carries the frontmatter a skill needs" \
	"$(sed -n 1p .claude/skills/pidly/SKILL.md)" "---"
check "with a name" "$(count 'name: pidly' .claude/skills/pidly/SKILL.md)" "1"
check "and a description saying when to use it" \
	"$(count 'description: Use when' .claude/skills/pidly/SKILL.md)" "1"
has "it teaches the loop" "$(cat .claude/skills/pidly/SKILL.md)" "pidly claim 7"
has "including the handoff" "$(cat .claude/skills/pidly/SKILL.md)" "pidly release -m"
has "and the rule that cannot be undone" \
	"$(cat .claude/skills/pidly/SKILL.md)" "Never delete a ticket"
has "it points at the reference rather than restating it" \
	"$(cat .claude/skills/pidly/SKILL.md)" ".pidly/README.md"
has "and tells a subagent to claim with a lease" \
	"$(cat .claude/skills/pidly/SKILL.md)" "PIDLY_AGENT"

echo "permissions"
check "a project with no settings.json gets one" \
	"$([ -f .claude/settings.json ] && echo yes)" "yes"
has "allowing a read-only command" "$(cat .claude/settings.json)" '"Bash(pidly list:*)"'
hasnt "and not one that writes" "$(cat .claude/settings.json)" "pidly close"
# It is the project's file, and JSON this script has no business parsing.
printf '{ "model": "opus" }\n' > .claude/settings.json
out=$($PIDLY claude)
check "an existing one is never rewritten" "$(cat .claude/settings.json)" '{ "model": "opus" }'
has "the block is printed instead" "$out" '"Bash(pidly list:*)"'
has "with somewhere to put it" "$out" "yours to edit"

echo "check compares them"
check "a freshly written set is clean" "$($PIDLY check >/dev/null && echo clean)" "clean"
printf 'tampered\n' >> .claude/commands/pidly-next.md
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "a drifted file is a finding" "$rc" "1"
has "naming the file and the fix" "$out" ".claude/commands/pidly-next.md is out of date"
$PIDLY claude >/dev/null
check "and regenerating settles it" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "a project that never asked"
rm -rf .claude
check "is not missing anything" "$($PIDLY check >/dev/null && echo clean)" "clean"
check "and init does not install it uninvited" \
	"$($PIDLY init >/dev/null; [ -d .claude ] && echo yes || echo no)" "no"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
