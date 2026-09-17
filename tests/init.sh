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
check "seeds the schema" "$([ -f .pidly/schema ] && echo yes)" "yes"
check "writes the reference" "$(count 'State is location' .pidly/README.md)" "1"
check "writes the AGENTS.md summary" "$(count '<!-- pidly:begin -->' AGENTS.md)" "1"

echo "ignore rules"
check "ignore rules live inside the tracker" "$([ -f .pidly/.gitignore ] && echo yes)" "yes"
check "locks are ignored" "$(grep -c '^\.lock$' .pidly/.gitignore)" "1"
check "lock temp files too" "$(grep -c '^\.lock\.\*$' .pidly/.gitignore)" "1"
check "and the fallback id" "$(grep -c '^\.id$' .pidly/.gitignore)" "1"
check "nothing is written to a root .gitignore" "$([ -f .gitignore ] && echo yes || echo no)" "no"

echo "the seeded schema"
check "has no extension, so no editor reflows it" \
	"$([ -f .pidly/schema.md ] && echo yes || echo no)" "no"
check "explains the structural lines it does not declare" \
	"$(count 'claim:, needs: and title:' .pidly/schema)" "1"
check "ships the handoff field as a stanza" \
	"$(grep -c '^field: handoff$' .pidly/schema)" "1"
check "and nothing else opinionated" "$(grep -c '^field: effort' .pidly/schema || true)" "0"
check "which check reads without complaint" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "the number registry"
check "init creates it" "$([ -d .pidly/.n ] && echo yes)" "yes"
check "it is not in the ignore rules" "$(grep -c '^\.n' .pidly/.gitignore || true)" "0"

echo "usable immediately"
n=$($PIDLY new "first" </dev/null | cut -f1)
check "a ticket can be created straight away" "$n" "1"
check "every declared field gets a slot, optional ones empty" \
	"$(grep -c '^handoff:$' .pidly/1/info || true)" "1"
check "the number is registered" "$([ -f .pidly/.n/1 ] && echo yes)" "yes"
check "with a nonce and the title" \
	"$(awk '{print (NF>=2 && $1 ~ /^[a-z0-9]+$/) ? "yes" : "no"}' .pidly/.n/1)" "yes"

mkdir .pidly/9
printf 'claim:\nneeds:\ntitle: made by hand\n' > .pidly/9/info
$PIDLY init >/dev/null
check "init backfills a hand-made ticket" "$([ -f .pidly/.n/9 ] && echo yes)" "yes"
n=$($PIDLY new "after backfill" </dev/null | cut -f1)
check "and the next number clears it" "$n" "10"
rm -rf .pidly/10 .pidly/.n/10
rm -rf .pidly/9
n=$($PIDLY new "after a delete" </dev/null | cut -f1)
check "a deleted ticket's number is never reissued" "$n" "10"

echo "refreshing"
printf '\nfield: effort\nrequired: yes\nmatch: S|M|L\n' >> .pidly/schema
printf 'clobbered\n' > .pidly/README.md
printf 'stale\n' > .pidly/.gitignore
$PIDLY init >/dev/null
check "the schema is left alone once it exists" "$(count 'field: effort' .pidly/schema)" "1"
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
