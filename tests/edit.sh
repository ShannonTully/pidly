#!/bin/sh
# Tests for edit: the three ways a body changes, and the two things the
# command adds over doing it by hand — the lock and a structural read of what
# was saved.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
. "$(dirname "$0")/lib.sh"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF "$3"; then no "$1 (unexpected '$3')"; else ok "$1"; fi; }
body() { awk 'b { print } !b && $0 == "" { b = 1 }' .pidly/1/info; }
# The header and the project's fields. updated is left out on purpose: pidly
# maintains it, so a write is meant to move it and nothing else.
head3() { awk 'NR>3 && $0 == "" { exit } !/^updated: /' .pidly/1/info; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pidly.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null
printf 'The first thing.\n' | $PIDLY new "first" >/dev/null       # 1
$PIDLY new "second" </dev/null >/dev/null                         # 2

echo "replacing a body"
before=$(head3)
out=$(printf 'A new body.\n\nWith a blank line in it.\n' | $PIDLY edit -b 1)
has "says so" "$out" "1 updated"
check "the body is the new one" "$(body)" "A new body.

With a blank line in it."
check "the header and fields are untouched" "$(head3)" "$before"
check "except the stamp pidly maintains" \
	"$(sed -n 's/^updated: //p' .pidly/1/info | wc -l | tr -d ' ')" "1"
check "check still passes" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "appending"
printf 'Appended.\n' | $PIDLY edit -a 1 >/dev/null
check "what was there stays" "$(body | head -1)" "A new body."
check "and the new text lands at the end" "$(body | tail -1)" "Appended."
check "separated by a blank line" "$(body | tail -2 | head -1)" ""

echo "a ticket with no body"
printf 'Started from nothing.\n' | $PIDLY edit -a 2 >/dev/null
check "gains one, with its separator" \
	"$(awk 'b { print } !b && $0 == "" { b = 1 }' .pidly/2/info)" "Started from nothing."
check "and is still valid" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "emptying a body"
: | $PIDLY edit -b 2 >/dev/null
check "leaves no body" "$(awk 'b { print } !b && $0 == "" { b = 1 }' .pidly/2/info)" ""
check "and a valid ticket" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "the editor"
cat > ed-append <<'ED'
#!/bin/sh
printf '\nFrom the editor.\n' >> "$1"
ED
chmod +x ed-append
out=$(EDITOR="$tmp/ed-append" $PIDLY edit 1)
has "an accepted edit is installed" "$out" "1 updated"
check "with the editor's text in the body" "$(body | tail -1)" "From the editor."

cat > ed-nothing <<'ED'
#!/bin/sh
exit 0
ED
chmod +x ed-nothing
out=$(EDITOR="$tmp/ed-nothing" $PIDLY edit 1)
has "an editor that changes nothing says so" "$out" "1 unchanged"

cat > ed-mangle <<'ED'
#!/bin/sh
# A standalone editor stub, so it spells out the portable in-place edit
# rather than sourcing the suite's lib.sh.
sed '3s/.*/no longer a title line/' "$1" > "$1.ed" && mv "$1.ed" "$1"
ED
chmod +x ed-mangle
before=$(cat .pidly/1/info)
out=$(EDITOR="$tmp/ed-mangle" $PIDLY edit 1 2>&1) && rc=0 || rc=$?
check "a saved file that is not a ticket is refused" "$rc" "1"
has "naming the fault" "$out" "1: line 3 is not title:"
has "and where the edit was kept" "$out" "your edit is in"
check "the ticket is untouched" "$(cat .pidly/1/info)" "$before"
draft=$(printf '%s' "$out" | sed -n 's/.*your edit is in //p')
check "and the draft really is there" "$([ -f "$draft" ] && echo yes)" "yes"
has "holding what was typed" "$(cat "$draft")" "no longer a title line"
rm -f "$draft"

cat > ed-racer <<'ED'
#!/bin/sh
# Someone claims the ticket while the editor is open.
sed '1s/.*/claim:999.1@elsewhere/' "$PIDLY_RACE_TARGET" > "$PIDLY_RACE_TARGET.ed"
mv "$PIDLY_RACE_TARGET.ed" "$PIDLY_RACE_TARGET"
printf '\nFrom a doomed edit.\n' >> "$1"
ED
chmod +x ed-racer
before=$(cat .pidly/1/info)
out=$(PIDLY_RACE_TARGET=.pidly/1/info EDITOR="$tmp/ed-racer" $PIDLY edit 1 2>&1) && rc=0 || rc=$?
check "an edit over a changed ticket is refused" "$rc" "1"
has "saying what happened" "$out" "changed while the editor was open"
check "the other write survives" "$(sed -n 1p .pidly/1/info)" "claim:999.1@elsewhere"
check "and the edit is not in the file" \
	"$(grep -c 'From a doomed edit' .pidly/1/info || true)" "0"
sedi '1s/.*/claim:/' .pidly/1/info
rm -f "$(printf '%s' "$out" | sed -n 's/.*your edit is in //p')"

echo "no editor to run"
out=$(env -u EDITOR -u VISUAL $PIDLY edit 1 </dev/null 2>&1) && rc=0 || rc=$?
check "is refused rather than hanging" "$rc" "1"
has "pointing at the non-interactive path" "$out" "use -b or -a"

echo "afterwards"
check "the tracker is still clean" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "replacing one passage"
$PIDLY new "passages" >/dev/null <<'B'
First paragraph, long enough that the body has some size to it and the
truncation guard below has something to protect.

Second paragraph, the one to replace.

Third paragraph, also present and also reasonably long.
B
pn=$($PIDLY list -a | awk 'END{print $1}')
$PIDLY edit -r "Second paragraph, the one to replace." -w "Replaced." "$pn" >/dev/null
has "the passage is replaced" "$($PIDLY show -b "$pn")" "Replaced."
hasnt "and the old text is gone" "$($PIDLY show -b "$pn")" "the one to replace"
has "the paragraphs around it survive" "$($PIDLY show -b "$pn")" "Third paragraph"
# The header is not part of the body, and folding it in would duplicate it.
check "the header is untouched" "$(sed -n 3p "$($PIDLY show -p "$pn")/info")" "title: passages"
check "and check is content" "$($PIDLY check >/dev/null && echo clean)" "clean"

out=$($PIDLY edit -r "nowhere in this body" -w "x" "$pn" 2>&1) && rc=0 || rc=$?
check "a passage that is absent is refused" "$rc" "1"
has "and says so" "$out" "not in the body"
out=$($PIDLY edit -r "paragraph" -w "x" "$pn" 2>&1) && rc=0 || rc=$?
check "a passage appearing twice is refused, not guessed at" "$rc" "1"
has "and asks for more of it" "$out" "more than once"
out=$($PIDLY edit -w "x" "$pn" 2>&1) && rc=0 || rc=$?
check "-w without -r is refused" "$rc" "1"

# Literal, not a regex: a body quotes patterns constantly.
$PIDLY edit -a "$pn" <<'B' >/dev/null
A line with [0-9]+ and .* in it.
B
$PIDLY edit -r "[0-9]+ and .*" -w "digits and anything" "$pn" >/dev/null
has "-r matches literally, not as a regex" \
	"$($PIDLY show -b "$pn")" "A line with digits and anything in it."

echo "the truncation guard"
before=$($PIDLY show -b "$pn")
out=$(printf 'tiny\n' | $PIDLY edit -b "$pn" 2>&1) && rc=0 || rc=$?
check "a body that lost most of itself is refused" "$rc" "1"
has "and says both sizes" "$out" "re-run with -f"
check "and the body is untouched" "$($PIDLY show -b "$pn")" "$before"
printf 'tiny\n' | $PIDLY edit -f -b "$pn" >/dev/null
check "-f says you meant it" "$($PIDLY show -b "$pn")" "tiny"

$PIDLY new "small" >/dev/null <<'B'
a short body
B
sn=$($PIDLY list -a | awk 'END{print $1}')
printf 'x\n' | $PIDLY edit -b "$sn" >/dev/null && rc=0 || rc=$?
check "a body with little to lose is not policed" "$rc" "0"
printf 'appended\n' | $PIDLY edit -a "$pn" >/dev/null && rc=0 || rc=$?
check "append is never guarded" "$rc" "0"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
