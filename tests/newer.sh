#!/bin/sh
# Tests for what check does with a tracker a newer pidly wrote.
#
# check is the only version-sensitive part of pidly. Everything else degrades
# because it is files: an older build can read, claim, close and reopen a
# tracker a newer one wrote. check could not, because it enforced a closed
# world — a field it had never heard of was a finding, so a build older than
# the tracker failed it, loudly and wrongly, for whoever cloned the repository
# rather than for whoever upgraded.
#
# The decision is that check reports damage and a version gap is not damage.
# An unknown field is a note: printed, because it is worth seeing, and not a
# reason to fail. The tracker records no format version and must not, so check
# can only suggest the reason, which is what it does.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/lib.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF "$3"; then no "$1 (found '$3')"; else ok "$1"; fi; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null
$PIDLY new "first" </dev/null >/dev/null    # 1
$PIDLY new "second" </dev/null >/dev/null   # 2

echo "a field this build does not know"
# Named for something no build declares. A field the format owns — defer, say
# — would be known here and prove nothing.
insert_after 3 .pidly/1/info 'severity: high'
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "does not fail a tracker that is otherwise clean" "$rc" "0"
has "and is still printed, as a note" "$out" \
	"note: 1: field 'severity' is not in the schema"
has "with the reason it is most likely to be" "$out" \
	"this tracker may have been written by a newer pidly"
has "and the other reason it might be" "$out" "the schema may be missing a stanza"
check "the tracker still reports as ok" \
	"$(printf '%s' "$out" | grep -c '^ok: 2 tickets')" "1"

echo "it is a note, not an excuse"
# Softening the unknown field must not soften anything else, or the exit
# status stops meaning anything and CI stops being worth running.
sedi 's/^title: second/nottitle: second/' .pidly/2/info
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "a real fault alongside it still fails" "$rc" "1"
has "the fault is reported as a problem" "$out" "2: line 3 is not title:"
has "and the unknown field is still only a note" "$out" \
	"note: 1: field 'severity' is not in the schema"
check "the count counts the fault and not the note" \
	"$(printf '%s' "$out" | grep -c '^1 problem(s)')" "1"
sedi 's/^nottitle: second/title: second/' .pidly/2/info

echo "and it is not mentioned when there is nothing to mention"
sedi '/^severity:/d' .pidly/1/info
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "a tracker with no unknown fields passes" "$rc" "0"
hasnt "without the suggestion" "$out" "newer pidly"
hasnt "and with no notes at all" "$out" "is not in the schema"

echo "the whole schema missing, which is what an old build sees"
# The case the decision exists for. A build from before the schema moved
# cannot find it, so every declared field reads as unknown. That used to be a
# finding per field per ticket — a wall of errors, all of them wrong. What is
# left is the one true finding: this build cannot find the schema.
cp -R .pidly "$tmp/keep"
rm .pidly/schema
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
has "the missing schema is still a finding" "$out" "does not exist"
check "and it is the only one" \
	"$(printf '%s' "$out" | grep -c '^1 problem(s)')" "1"
has "every field of every ticket is a note" "$out" \
	"note: 1: field 'handoff' is not in the schema"
has "including the other ticket's" "$out" \
	"note: 2: field 'handoff' is not in the schema"
rm -rf .pidly && cp -R "$tmp/keep" .pidly && rm -rf "$tmp/keep"

echo "edit is the same rule from the other side"
# edit reads everything info_faults prints on stdout as a reason to refuse the
# save, so a note has to reach it another way or an older build could never
# edit a newer tracker — the same stranger-hostile failure, one command over.
cat > "$tmp/ed-addfield" <<'ED'
#!/bin/sh
# The one-line "3a text" form is GNU only, which portable.sh forbids and this
# file is not exempt from. head and sed -n are what lib.sh uses for the same
# job; an editor script cannot source it.
{ head -n 3 "$1"; printf 'impact: wide\n'; sed -n '4,$p' "$1"; } > "$1.n" &&
	mv "$1.n" "$1"
ED
chmod +x "$tmp/ed-addfield"
out=$(EDITOR="$tmp/ed-addfield" $PIDLY edit 1 2>&1) && rc=0 || rc=$?
check "a ticket gaining an unknown field is saved" "$rc" "0"
has "and the note is said out loud" "$out" "note: 1: field 'impact' is not in the schema"
check "the field is on disk, with its value untouched" \
	"$(sed -n 's/^impact: //p' .pidly/1/info)" "wide"

cat > "$tmp/ed-break" <<'ED'
#!/bin/sh
sed '3s/.*/not a title line/' "$1" > "$1.n" && mv "$1.n" "$1"
ED
chmod +x "$tmp/ed-break"
out=$(EDITOR="$tmp/ed-break" $PIDLY edit 2 2>&1) && rc=0 || rc=$?
check "but real damage is still refused" "$rc" "1"
has "naming what broke" "$out" "2: line 3 is not title:"
check "and the ticket on disk is untouched" \
	"$(sed -n 3p .pidly/2/info)" "title: second"

echo "an unknown field's value is nobody's business"
# Nothing here knows what the field means, so nothing may judge its value. A
# value that would fail some other field's pattern must not be tested against
# it, and must survive being read and written.
sedi 's/^impact: wide/impact: XL/' .pidly/1/info
out=$($PIDLY check 2>&1) && rc=0 || rc=$?
check "a value that looks wrong for another field is not judged" "$rc" "0"
hasnt "and no pattern is blamed for it" "$out" "does not match"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
