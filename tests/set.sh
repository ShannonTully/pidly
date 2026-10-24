#!/bin/sh
# Tests for `pidly set` and `pidly fields`: writing one field, and rolling a
# schema row out to tickets that predate it.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/lib.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF "$3"; then no "$1 (unexpected '$3')"; else ok "$1"; fi; }
fieldnames() { awk 'NR>3 { if ($0 == "") exit; sub(/:.*/, ":"); print }' "$1" | tr '\n' ' '; }
body() { awk 'b { print } !b && $0 == "" { b = 1 }' "$1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null
printf '\nfield: effort\nrequired: yes\nmatch: S|M|L\n' >> .pidly/schema
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
sedi 's/^updated: .*/updated: 2020-01-01T00:00:00Z/' .pidly/2/info
$PIDLY set 2 effort M >/dev/null
hasnt "writing a field is activity, so updated moves" \
	"$(sed -n 's/^updated: //p' .pidly/2/info)" "2020-01-01T00:00:00Z"

out=$($PIDLY set 1 effort 2>&1) && rc=0 || rc=$?
check "clearing a required field is refused" "$rc" "1"
has "and says what to do instead" "$out" "required"
check "so the value survives" "$(sed -n 's/^effort: //p' .pidly/1/info)" "L"
out=$($PIDLY set 1 nosuch x 2>&1) && rc=0 || rc=$?
check "a field the schema does not declare is refused" "$rc" "1"
has "and says where names come from" "$out" "the schema"
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
printf '\nfield: area\nmatch: cli|docs\n' >> .pidly/schema

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
	"$(grep -l '^area' .pidly/1/info .pidly/c/2/info .pidly/3/info | wc -l)" "3"
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
delete_stanza area .pidly/schema
$PIDLY fields >/dev/null
check "a dropped schema row does not delete the value" \
	"$(sed -n 's/^area: //p' .pidly/1/info)" "docs"

echo "the format's own lines"
$PIDLY new -f effort=M "three" </dev/null >/dev/null   # 3
$PIDLY set 1 title "a better title" >/dev/null
check "set writes the title on line 3" \
	"$(sed -n 3p .pidly/1/info)" "title: a better title"
out=$($PIDLY set 1 title 2>&1) && rc=0 || rc=$?
check "title cannot be cleared" "$rc" "1"

# awk -v processes escapes; the value has to reach the file unchanged.
$PIDLY set 1 title 'a \t and a backslash \\ kept' >/dev/null
check "a title keeps its backslashes" \
	"$(sed -n 3p .pidly/1/info)" 'title: a \t and a backslash \\ kept'
$PIDLY set 1 title "one" >/dev/null

$PIDLY set 1 needs "2 3" >/dev/null
check "set writes needs on line 2" "$(sed -n 2p .pidly/1/info)" "needs: 2 3"
check "needs lists one a line" "$($PIDLY needs 1 | tr '\n' ' ')" "2 3 "
out=$($PIDLY set 1 needs "99" 2>&1) && rc=0 || rc=$?
check "a dependency on a ticket that does not exist is refused" "$rc" "1"
has "and says which" "$out" "no ticket 99"
check "and the line is untouched" "$(sed -n 2p .pidly/1/info)" "needs: 2 3"
out=$($PIDLY set 1 needs "1" 2>&1) && rc=0 || rc=$?
check "a ticket cannot need itself" "$rc" "1"

# Ticket 2 is closed by an earlier test, so it is located, not assumed —
# and a closed ticket's dependencies are still editable.
$PIDLY needs -a 3 2 >/dev/null
check "-a adds one, even on a closed ticket" \
	"$(sed -n 2p "$($PIDLY show -p 2)/info")" "needs: 3"
$PIDLY set 2 needs "" >/dev/null
check "needs clears to a bare key" \
	"$(sed -n 2p "$($PIDLY show -p 2)/info")" "needs:"
out=$($PIDLY needs -a 2 1 2>&1) && rc=0 || rc=$?
check "adding one already there is refused" "$rc" "1"
out=$($PIDLY needs -d 99 1 2>&1) && rc=0 || rc=$?
check "dropping one not there is refused" "$rc" "1"
$PIDLY needs -d 2 1 >/dev/null
check "-d drops one and keeps the rest" "$(sed -n 2p .pidly/1/info)" "needs: 3"

out=$($PIDLY set 1 claim "x" 2>&1) && rc=0 || rc=$?
check "claim is not set by hand" "$rc" "1"
has "and says who writes it" "$out" "claim, release and reap"
# No check-is-clean assertion here: the test above deliberately leaves a
# value whose stanza the schema no longer declares, which check reports and
# should. The needs and title writes are verified line by line instead.

echo "values reach the file unchanged"
# awk -v processes escape sequences, so these used to be rewritten silently:
# \t arrived as a tab, \\ as one backslash, and the line was still a legal
# field so check had nothing to say about it.
$PIDLY new -f effort=M "escapes" </dev/null >/dev/null
en=$($PIDLY list -a | awk 'END{print $1}')
for v in 'a \t and \\ here' 'ends with a backslash \' 'a [0-9]{4} and .* and $0' 'tabs	and  spaces'; do
	$PIDLY set "$en" area "$v" >/dev/null 2>&1 ||
		{ printf '\nfield: area\n' >> .pidly/schema; $PIDLY fields >/dev/null
		  $PIDLY set "$en" area "$v" >/dev/null; }
	check "a value survives: $v" "$($PIDLY show -f area "$en")" "$v"
done
check "and check is content with all of it" \
	"$($PIDLY check >/dev/null 2>&1 && echo clean)" "clean"

# index() finds the line literally; sub() used to cut it with a regex built
# from the key, and the two disagree when the key holds a metacharacter.
f=$($PIDLY show -p "$en")/info
awk 'NR==4 { print "a+b: the value" } { print }' "$f" > "$f.t" && mv "$f.t" "$f"
check "a field name holding a metacharacter is cut literally" \
	"$($PIDLY show -f 'a+b' "$en")" "the value"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
