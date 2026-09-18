#!/bin/sh
# Tests for the manual page: that it is generated rather than written, that it
# is valid roff, and that check notices when a shipped copy goes stale.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/lib.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null

echo "the page"
$PIDLY man > page.1
has "opens with a .TH" "$(head -n 1 page.1)" ".TH PIDLY 1"
has "names the tool" "$(cat page.1)" "pidly \- a ticket tracker"
for sect in NAME SYNOPSIS DESCRIPTION COMMANDS ENVIRONMENT FILES "EXIT STATUS" "SEE ALSO"; do
	has "has a $sect section" "$(cat page.1)" ".SH $sect"
done

# The whole point of generating it: the command list cannot drift from the
# one the CLI prints, because there is only one of them.
check "every command in the usage text is in the page" "$(
	$PIDLY help 2>&1 | awk 'NR>2 && /^  [a-z]/ { print $1 }' | sort -u |
	while read -r c; do grep -qF "  $c" page.1 || echo "missing $c"; done
)" ""
has "and the environment section came along" "$(cat page.1)" "PIDLY_LEASE"
# SYNOPSIS says it already; repeating it opens COMMANDS like a paste.
check "the usage: line is not repeated into COMMANDS" \
	"$(awk '/^.SH COMMANDS/,/^.SH ENVIRONMENT/' page.1 | grep -c '^usage: pidly')" "0"

echo "valid roff"
# Roff reads a backslash as markup and a leading . or ' as a control line, so
# nothing from the usage text may reach the page unescaped.
check "no raw non-ASCII survives" \
	"$(LC_ALL=C grep -c '[^ -~	]' page.1 || true)" "0"
has "the em-dash became an roff escape" "$(cat page.1)" '\(em'
check "no line inside a .nf block starts with a bare dot" "$(
	awk '/^\.nf$/ { inb = 1; next } /^\.fi$/ { inb = 0; next }
	     inb && /^\./ { print "bare dot: " $0 }' page.1
)" ""
if command -v groff >/dev/null 2>&1; then
	err=$(groff -man -Tutf8 -ww page.1 2>&1 >/dev/null || true)
	check "groff renders it without a warning" "$err" ""
	has "and the rendering has the command list" \
		"$(groff -man -Tutf8 page.1 2>/dev/null | col -bx)" "take ticket n"
else
	ok "groff not installed, skipping the render (2 tests)"
	pass=$((pass+2))
fi

echo "it stays in step"
# Nothing in the page may be dated or versioned: a .TH carrying today's date
# would differ from yesterday's committed copy every day, and check would
# report drift that is not drift.
$PIDLY man > again.1
check "two runs are byte-identical" "$(cmp -s page.1 again.1 && echo same)" "same"

mkdir -p docs && cp page.1 docs/pidly.1
check "check is content with a current page" \
	"$($PIDLY check >/dev/null 2>&1 && echo clean)" "clean"
printf 'tampered\n' >> docs/pidly.1
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "a stale page is reported" "$rc" "1"
has "and says how to fix it" "$out" "run 'pidly man > docs/pidly.1'"
rm -rf docs
check "a project with no page is not nagged" \
	"$($PIDLY check >/dev/null 2>&1 && echo clean)" "clean"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
