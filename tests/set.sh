#!/bin/sh
# Tests for `pidly set` and `pidly fields`: writing one field, and rolling a
# schema row out to tickets that predate it.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF "$3"; then no "$1 (unexpected '$3')"; else ok "$1"; fi; }
fieldnames() { awk 'NR>3 { if ($0 == "") exit; sub(/:.*/, ":"); print }' "$1" | tr '\n' ' '; }
body() { awk 'b { print } !b && $0 == "" { b = 1 }' "$1"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null
printf '| effort | yes      | S, M, L |\n' >> .pidly/schema.md
$PIDLY new -f effort=M "one" </dev/null >/dev/null
$PIDLY new -f effort=S "two" </dev/null >/dev/null

echo "set"
$PIDLY set 1 effort L >/dev/null
check "replaces a value" "$(sed -n 's/^effort: //p' .pidly/1/info)" "L"
$PIDLY set 1 handoff "got as far as the lexer" >/dev/null
check "a value may contain spaces" \
	"$(sed -n 's/^handoff: //p' .pidly/1/info)" "got as far as the lexer"
check "it lands in the field block, not the body" \
	"$(fieldnames .pidly/1/info)" "created: updated: handoff: effort: "
$PIDLY set 1 handoff >/dev/null
check "no value clears it" "$(grep -c '^handoff:$' .pidly/1/info || true)" "1"
check "and leaves a bare key, not a trailing space" \
	"$(grep -c '^handoff: $' .pidly/1/info || true)" "0"
check "the ticket is still readable to check" "$($PIDLY check >/dev/null 2>&1 && echo ok)" "ok"

before=$(sed -n 's/^updated: //p' .pidly/2/info)
sed -i 's/^updated: .*/updated: 2020-01-01T00:00:00Z/' .pidly/2/info
$PIDLY set 2 effort M >/dev/null
hasnt "writing a field is activity, so updated moves" \
	"$(sed -n 's/^updated: //p' .pidly/2/info)" "2020-01-01T00:00:00Z"

out=$($PIDLY set 1 effort 2>&1) && rc=0 || rc=$?
check "clearing a required field is refused" "$rc" "1"
has "and says what to do instead" "$out" "required"
check "so the value survives" "$(sed -n 's/^effort: //p' .pidly/1/info)" "L"
out=$($PIDLY set 1 nosuch x 2>&1) && rc=0 || rc=$?
check "a field the schema does not declare is refused" "$rc" "1"
has "and says where names come from" "$out" "schema.md"
out=$($PIDLY set 1 updated 2026-01-01T00:00:00Z 2>&1) && rc=0 || rc=$?
check "pidly's own stamps are not set's to write" "$rc" "1"
out=$($PIDLY set 1 handoff "two
lines" 2>&1) && rc=0 || rc=$?
check "a multi-line value is refused" "$rc" "1"
out=$($PIDLY set 99 effort M 2>&1) && rc=0 || rc=$?
check "an unknown ticket is refused" "$rc" "1"

echo "fields"
# A ticket written by hand, with its fields in an order of its own and a
# stamp the schema does not mention first.
mkdir .pidly/3
printf 'claim:\nneeds:\ntitle: hand made\neffort: S\ncreated: 2020-01-01T00:00:00Z\n\nbody line\n' \
	> .pidly/3/info
printf 'abc123 hand made\n' > .pidly/.n/3
mkdir -p .pidly/c && mv .pidly/2 .pidly/c/          # and one that is finished
printf '| area | no       | cli, docs |\n' >> .pidly/schema.md

out=$($PIDLY check 2>&1 || true)
has "check reports the drift a new schema row leaves" "$out" "have no 'area' line"
has "counting the tickets rather than listing them" "$out" "3 ticket(s)"
has "as a note" "$out" "note: "
$PIDLY check >/dev/null 2>&1 && rc=0 || rc=$?
check "which does not fail check: a hand-made ticket is a legal ticket" "$rc" "0"

$PIDLY set 1 area cli >/dev/null                     # one ticket already has it
was=$(sed -n 's/^updated: //p' .pidly/c/2/info)
out=$($PIDLY fields)
has "the migration reports what it added" "$out" "3     + handoff area"
hasnt "and leaves the ticket that already had it alone" "$out" "1     +"
check "every ticket now has the slot" \
	"$(grep -lc '^area' .pidly/1/info .pidly/c/2/info .pidly/3/info | wc -l)" "3"
check "a closed ticket is migrated too" "$(grep -c '^area:$' .pidly/c/2/info || true)" "1"
check "the value a ticket already had is untouched" \
	"$(sed -n 's/^area: //p' .pidly/1/info)" "cli"
check "updated is not bumped: a migration is not activity" \
	"$(sed -n 's/^updated: //p' .pidly/c/2/info)" "$was"

# Its own lines never move: effort still precedes created, which the schema
# orders the other way round. The added keys land in schema order relative to
# what is there — handoff before effort, area after it.
check "a hand-made ticket keeps its own order" \
	"$(fieldnames .pidly/3/info)" "handoff: effort: created: area: "
check "and its body" "$(body .pidly/3/info)" "body line"
out=$($PIDLY fields)
has "a second run has nothing to do" "$out" "already has every declared field"
check "and check is clean" "$($PIDLY check >/dev/null 2>&1 && echo ok)" "ok"

# A field the schema stopped declaring is data, not drift.
$PIDLY set 1 area docs >/dev/null
sed -i '/^| area /d' .pidly/schema.md
$PIDLY fields >/dev/null
check "a dropped schema row does not delete the value" \
	"$(sed -n 's/^area: //p' .pidly/1/info)" "docs"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
