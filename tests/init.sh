#!/bin/sh
# Tests for `pidly init`: creating a tracker, and refreshing one without
# destroying what the project owns.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
count() { c=$(grep -cF "$1" "$2" 2>/dev/null || true); printf '%s' "${c:-0}"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

echo "creating"
$PIDLY init >/dev/null
check "makes .pidly" "$([ -d .pidly ] && echo yes)" "yes"
check "seeds schema.md" "$([ -f .pidly/schema.md ] && echo yes)" "yes"
check "writes the reference" "$(count 'State is location' .pidly/README.md)" "1"
check "writes the AGENTS.md summary" "$(count '<!-- pidly:begin -->' AGENTS.md)" "1"

echo "ignore rules"
check "ignore rules live inside the tracker" "$([ -f .pidly/.gitignore ] && echo yes)" "yes"
check "locks are ignored" "$(grep -c '^\.lock$' .pidly/.gitignore)" "1"
check "lock temp files too" "$(grep -c '^\.lock\.\*$' .pidly/.gitignore)" "1"
check "and the fallback id" "$(grep -c '^\.id$' .pidly/.gitignore)" "1"
check "nothing is written to a root .gitignore" "$([ -f .gitignore ] && echo yes || echo no)" "no"

echo "the seeded schema"
check "documents the four header lines" "$(count 'desc:' .pidly/schema.md)" "1"
check "ships the handoff field" "$(count '| handoff ' .pidly/schema.md)" "1"
check "and nothing else opinionated" "$(grep -c '^| effort' .pidly/schema.md || true)" "0"

echo "usable immediately"
n=$($PIDLY new "first" </dev/null | cut -f1)
check "a ticket can be created straight away" "$n" "1"
check "handoff is optional, so not stubbed" "$(grep -c '^handoff' .pidly/1/info || true)" "0"

echo "refreshing"
printf '| effort | yes | S,M,L |\n' >> .pidly/schema.md
printf 'clobbered\n' > .pidly/README.md
printf 'stale\n' > .pidly/.gitignore
$PIDLY init >/dev/null
check "schema.md is left alone once it exists" "$(count '| effort ' .pidly/schema.md)" "1"
check "the reference is regenerated" "$(count 'State is location' .pidly/README.md)" "1"
check "the ignore rules are regenerated" "$(grep -c '^\.lock$' .pidly/.gitignore)" "1"
check "existing tickets survive" "$([ -f .pidly/1/info ] && echo yes)" "yes"
out=$($PIDLY init 2>&1)
case $out in *refreshed*) ok "and it says it refreshed rather than created" ;;
             *) no "output was: $out" ;; esac

echo "nesting"
mkdir -p sub/deeper
( cd sub/deeper && $PIDLY init >/dev/null 2>&1 ) && rc=0 || rc=$?
check "a tracker inside a tracker is refused" "$rc" "1"
check "and nothing is created" "$([ -d sub/deeper/.pidly ] && echo yes || echo no)" "no"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
