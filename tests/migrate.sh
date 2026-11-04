#!/bin/sh
# Tests for migrate: importing a tracker from somewhere else.
#
# The corpus here is written by hand rather than borrowed, so the suite says
# what it depends on. The real one it was developed against — 332 issues out
# of a beads export — is not in this repository and will not be.
#
# Two things are worth more than the mapping. The export is a snapshot, not
# the tracker, and one that is behind must not import quietly; and JSON is
# parsed by a scanner here, so the cases that break every regex — braces and
# quotes inside strings, escapes, a literal backslash-n — are the ones to pin.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/lib.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF -- "$3"; then no "$1 (found '$3')"; else ok "$1"; fi; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID

# info for the ticket whose origin is $1, wherever it ended up.
find_origin() { grep -rl "^origin: $1\$" .pidly --include=info | head -n 1; }
field() { sed -n "s/^$2: //p" "$(find_origin "$1")"; }
body() { sed -n '/^$/,$p' "$(find_origin "$1")"; }
number() { p=$(find_origin "$1"); p=${p%/info}; printf '%s\n' "${p##*/}"; }

mkdir -p beads
cat > beads/issues.jsonl <<'JSONL'
{"_type":"issue","id":"p-1","title":"the parent","description":"A body with {braces}, a \"quoted\" word and a comma, which every regex splits on.","status":"open","priority":2,"issue_type":"epic","assignee":"ada","created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-02T00:00:00Z"}
{"_type":"issue","id":"p-2","title":"the child","description":"Escapes: \u003c \u003e \u0026 and a literal backslash-n \\n which is not a line break.","status":"closed","priority":1,"issue_type":"bug","assignee":"ada","created_at":"2026-01-03T00:00:00Z","updated_at":"2026-01-04T00:00:00Z","close_reason":"Closed","dependencies":[{"issue_id":"p-2","depends_on_id":"p-1","type":"parent-child","metadata":"{}"}]}
{"_type":"issue","id":"p-3","title":"blocked on the child","description":"line one\nline two","status":"open","priority":3,"issue_type":"task","created_at":"2026-01-05T00:00:00Z","updated_at":"2026-01-05T00:00:00Z","acceptance_criteria":"- it works","notes":"a note","design":"a design","labels":["alpha","beta"],"dependencies":[{"issue_id":"p-3","depends_on_id":"p-2","type":"blocked-by","metadata":"{}"}]}
{"_type":"issue","id":"p-4","title":"blocking the first","description":"","status":"in_progress","priority":2,"issue_type":"feature","created_at":"2026-01-06T00:00:00Z","updated_at":"2026-01-06T00:00:00Z","dependencies":[{"issue_id":"p-4","depends_on_id":"p-1","type":"blocks","metadata":"{}"}]}
{"_type":"issue","id":"p-5","title":"put off","description":"","status":"deferred","priority":4,"issue_type":"chore","created_at":"2026-01-07T00:00:00Z","updated_at":"2026-01-07T00:00:00Z"}
{"_type":"memory","key":"adr-1","value":"a document, not a ticket","created_at":"2026-01-08T00:00:00Z","created_by":"ada"}
JSONL
printf '{"last_dolt_commit":"abc","timestamp":"2026-01-09T00:00:00Z","issues":5,"memories":1}\n' \
	> beads/export-state.json

# The corpus has to still contain what it is here to exercise. \u003c decoding
# is where a portability bug lived — 0x80 is not a number in POSIX awk, so the
# decoder silently produced the string 000 — and an escape that got unescaped
# on its way into this file would make the test below pass without testing it.
grep -q 'u003c' beads/issues.jsonl ||
	{ echo "the corpus lost its unicode escapes"; exit 1; }
grep -qF 'backslash-n \\n which' beads/issues.jsonl ||
	{ echo "the corpus lost its literal backslash-n"; exit 1; }

echo "a fresh tracker takes it"
mkdir -p one && cd one
$PIDLY init >/dev/null
out=$($PIDLY migrate beads "$tmp/beads" 2>&1) && rc=0 || rc=$?
check "the import succeeds" "$rc" "0"
has "and says what it took" "$out" "imported 5 tickets"
has "counting open and closed" "$out" "4 open, 1 closed"
check "the tracker it made is valid" "$($PIDLY check >/dev/null 2>&1 && echo clean)" "clean"
check "and holds every issue" "$($PIDLY tree | grep -c .)" "5"

echo "what each ticket became"
check "the title survives" "$(field p-1 title)" "the parent"
check "created is the source's" "$(field p-1 created)" "2026-01-01T00:00:00Z"
check "updated too" "$(field p-1 updated)" "2026-01-02T00:00:00Z"
check "the old id is kept, so a commit message still resolves" \
	"$(field p-1 origin)" "p-1"
check "priority comes across" "$(field p-3 priority)" "3"
check "and the kind" "$(field p-2 kind)" "bug"
check "and the assignee" "$(field p-2 assignee)" "ada"
check "nothing arrives claimed" "$(grep -rc '^claim:$' .pidly --include=info | grep -c ':1')" "5"

echo "state is location, as it is everywhere else"
check "a closed issue is under a c/" \
	"$(find_origin p-2 | grep -c '/c/')" "1"
check "an open one is not" "$(find_origin p-1 | grep -c '/c/')" "0"

echo "the shapes a regex gets wrong"
has "braces, a quoted word and a comma survive a description" "$(body p-1)" \
	'A body with {braces}, a "quoted" word and a comma'
has "escaped angle brackets decode" "$(body p-2)" "Escapes: < > &"
# The one that decodes twice if the unescaping is a pile of gsubs: the source
# holds the two characters backslash and n, not a line break.
has "a literal backslash-n stays two characters" "$(body p-2)" \
	'backslash-n \n which is not'
check "and did not become a line break" "$(body p-2 | grep -c 'which is not')" "1"
check "a real newline is a real newline" "$(body p-3 | grep -c '^line two$')" "1"

echo "the parts with no home of their own"
has "acceptance criteria get a heading" "$(body p-3)" "## Acceptance criteria"
has "and their text" "$(body p-3)" "- it works"
has "notes too" "$(body p-3)" "## Notes"
has "and design" "$(body p-3)" "## Design"
# Labels are a set, and a set-valued field is deliberately unsolved here, so
# they go where prose goes rather than into a field pretending to be one.
has "labels land in the body" "$(body p-3)" "## Labels"
has "with every one of them" "$(body p-3)" "alpha, beta"
check "and no labels field is invented" \
	"$(grep -rc '^labels:' .pidly --include=info | grep -vc ':0' || true)" "0"

echo "the graph, renumbered"
check "a parent-child edge became nesting" \
	"$(find_origin p-2 | grep -c "/$(number p-1)/")" "1"
check "blocked-by became needs, by number" "$(field p-3 needs)" "$(number p-2)"
check "blocks became needs on the other ticket" "$(field p-1 needs)" "$(number p-4)"
hasnt "and no old id is left on a needs line" "$(grep -rh '^needs:' .pidly --include=info)" "p-"

echo "the states pidly does not have"
has "in_progress is imported unclaimed, and said so" "$out" "1 was in progress"
check "with nothing claiming it" "$(field p-4 claim)" ""
has "deferred is imported open, and said so" "$out" "1 deferred"
check "one of them, since only p-5 is" "$(find_origin p-5 | grep -c '/c/')" "0"
has "a memory record is not a ticket" "$out" "1 memory record(s) skipped"
check "and did not become one" "$(grep -rl '^origin: adr-1$' .pidly --include=info | grep -c . || true)" "0"

echo "the registry is filled, so no number is reissued"
check "one entry per ticket" "$(find .pidly/.n -type f | wc -l | tr -d ' ')" "5"
n=$($PIDLY new "after the import" </dev/null | awk '{print $1}')
check "and the next ticket does not collide" "$n" "6"
cd "$tmp"

echo "a tracker that already holds work is not a destination"
mkdir -p two && cd two
$PIDLY init >/dev/null
$PIDLY new "work already here" </dev/null >/dev/null
out=$($PIDLY migrate beads "$tmp/beads" 2>&1) && rc=0 || rc=$?
check "the import is refused" "$rc" "1"
has "saying why" "$out" "already has tickets"
check "and nothing was imported" "$($PIDLY tree | grep -c .)" "1"
cd "$tmp"

echo "an export that is behind the tracker it came from"
# .beads/*.jsonl is a snapshot somebody has to remember to refresh. Importing
# a stale one and reporting success is the failure this gate exists for: on
# the corpus this was built against it would have dropped a quarter of the
# tickets without a word.
mkdir -p stale && cp beads/issues.jsonl stale/
printf '{"last_dolt_commit":"abc","timestamp":"2026-01-09T00:00:00Z","issues":9,"memories":1}\n' \
	> stale/export-state.json
mkdir -p three && cd three
$PIDLY init >/dev/null
out=$($PIDLY migrate beads "$tmp/stale" 2>&1) && rc=0 || rc=$?
check "a count that disagrees with the file is refused" "$rc" "1"
has "and both numbers are shown" "$out" "declares  9"
has "with what to do about it" "$out" "bd export"
# bd export with no -o writes to stdout, so a remedy without it leaves the
# file as it was and the refusal repeats itself.
has "saying -o and naming the file" "$out" "bd export -o $tmp/stale/issues.jsonl"
has "and that bd export -o leaves the count behind" "$out" "does not update export-state.json"
check "nothing was written" "$($PIDLY tree | grep -c . || true)" "0"

# The sharper signal, and the one that needs no database: ids the interaction
# log names that the export does not contain were created after it was taken.
printf '{"id":"int-1","kind":"field_change","issue_id":"p-99","created_at":"2026-02-01T00:00:00Z"}\n' \
	> "$tmp/stale/interactions.jsonl"
printf '{"last_dolt_commit":"abc","timestamp":"2026-01-09T00:00:00Z","issues":5,"memories":1}\n' \
	> "$tmp/stale/export-state.json"
out=$($PIDLY migrate beads "$tmp/stale" 2>&1) && rc=0 || rc=$?
check "an id the log knows and the export does not is refused" "$rc" "1"
has "and counted" "$out" "1 ticket(s) the interaction log names are not in it"
check "where bd export -o does fix it, so --anyway is not offered as the way" \
	"$(printf '%s\n' "$out" | grep -c 'does not update' || true)" "0"

out=$($PIDLY migrate beads "$tmp/stale" --anyway 2>&1) && rc=0 || rc=$?
check "--anyway imports it" "$rc" "0"
has "while still saying it is behind" "$out" "importing anyway, as asked"
check "and the result is a valid tracker" \
	"$($PIDLY check >/dev/null 2>&1 && echo clean)" "clean"
cd "$tmp"

echo "a fresh export whose count bd left behind"
# What bd export -o leaves: the file current, export-state.json not. With a
# log naming nothing the file lacks, the count is a fact about bd's
# bookkeeping and not about the export, and refusing it would leave --anyway
# as the only way through for every real migration.
mkdir -p skew && cp beads/issues.jsonl skew/
printf '{"id":"int-1","kind":"field_change","issue_id":"p-1","created_at":"2026-02-01T00:00:00Z"}\n' \
	> skew/interactions.jsonl
printf '{"last_dolt_commit":"abc","timestamp":"2026-01-09T00:00:00Z","issues":9,"memories":1}\n' \
	> skew/export-state.json
mkdir -p skewed && cd skewed
$PIDLY init >/dev/null
out=$($PIDLY migrate beads "$tmp/skew" 2>&1) && rc=0 || rc=$?
check "it imports without --anyway" "$rc" "0"
has "saying the count disagrees" "$out" "export-state.json declares 9 issues"
has "and why that is not a refusal" "$out" "so it is current"
check "without calling the export behind" "$(printf '%s\n' "$out" | grep -c 'is behind' || true)" "0"
check "and the result is a valid tracker" \
	"$($PIDLY check >/dev/null 2>&1 && echo clean)" "clean"
cd "$tmp"

echo "a closed parent holding open work"
# pidly will not have a finished tree holding live work, and the two halves of
# the contradiction are not equal: the child says there is work left.
# The parent closed and the child open, which the corpus above is not.
mkdir -p conflict
awk '
	/"id":"p-1"/ { sub(/"status":"open"/, "\"status\":\"closed\"") }
	/"id":"p-2"/ { sub(/"status":"closed"/, "\"status\":\"open\"") }
	{ print }' beads/issues.jsonl > conflict/issues.jsonl
grep -q '"id":"p-1".*"status":"closed"' conflict/issues.jsonl ||
	{ echo "the conflict corpus was not built"; exit 1; }
grep -q '"id":"p-2".*"status":"open"' conflict/issues.jsonl ||
	{ echo "the conflict corpus was not built"; exit 1; }
mkdir -p four && cd four
$PIDLY init >/dev/null
out=$($PIDLY migrate beads "$tmp/conflict" 2>&1) && rc=0 || rc=$?
check "the import succeeds" "$rc" "0"
check "the parent is left open, because work under it is not done" \
	"$(find_origin p-1 | grep -c '/c/')" "0"
has "and it is reported rather than done silently" "$out" "left open"
check "and the tracker is valid" "$($PIDLY check >/dev/null 2>&1 && echo clean)" "clean"
cd "$tmp"

echo "sources it does not know"
mkdir -p five && cd five
$PIDLY init >/dev/null
out=$($PIDLY migrate github "$tmp/beads" 2>&1) && rc=0 || rc=$?
check "an unknown source is refused" "$rc" "1"
has "by name" "$out" "unknown source 'github'"
out=$($PIDLY migrate beads "$tmp/nothing-here" 2>&1) && rc=0 || rc=$?
check "and a directory with no export is too" "$rc" "1"
has "saying what to run" "$out" "bd export -o $tmp/nothing-here/issues.jsonl"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
