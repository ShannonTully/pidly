#!/bin/sh
# Tests for .pidly/schema: stanzas, patterns, and what check says about both.
set -eu
PIDLY=$(cd "$(dirname "$0")/.." && pwd)/bin/pidly
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }
has() { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else no "$1 (missing '$3' in: $2)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF "$3"; then no "$1 (unexpected '$3')"; else ok "$1"; fi; }
fieldnames() { awk 'NR>3 { if ($0 == "") exit; sub(/:.*/, ":"); print }' "$1" | tr '\n' ' '; }
schema() { cat > .pidly/schema; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
PIDLY_PID=$$; export PIDLY_PID
$PIDLY init >/dev/null
schema <<'EOF'
field: effort
match: S|M|L
note: rough size

field: due
match: [0-9]{4}-[0-9]{2}-[0-9]{2}

field: area
required: yes
match: format|cli|docs

field: handoff
EOF

echo "declarations"
$PIDLY new -f area=cli "one" </dev/null >/dev/null
check "new writes a slot per stanza, in declaration order" \
	"$(fieldnames .pidly/1/info)" "created: updated: effort: due: area: handoff: "
check "required: yes is read from the stanza" \
	"$(sed -n 's/^area: //p' .pidly/1/info)" "cli"
out=$($PIDLY new "two" </dev/null 2>&1) && rc=0 || rc=$?
check "and enforced" "$rc" "1"

echo "patterns"
check "a value inside its pattern is accepted" \
	"$($PIDLY set 1 effort M >/dev/null && echo ok)" "ok"
out=$($PIDLY set 1 effort XL 2>&1) && rc=0 || rc=$?
check "set refuses a value outside it" "$rc" "1"
has "and quotes the pattern" "$out" "must match S|M|L"
out=$($PIDLY new -f area=cli -f effort=XL "three" </dev/null 2>&1) && rc=0 || rc=$?
check "so does new -f: the two agree about what a value is" "$rc" "1"

# A pattern is matched anchored, which is the whole reason S|M|L is safe as a
# set: unanchored it would accept anything containing an M.
sed -i 's/^effort: M$/effort: M extra/' .pidly/1/info
out=$($PIDLY check 2>&1 || true)
has "check reports a value outside its pattern" "$out" \
	"1: effort is 'M extra', which does not match S|M|L"
sed -i 's/^effort: M extra$/effort: M/' .pidly/1/info

# grep, not awk: mawk has no interval expressions, so a schema written with
# {4} would silently match nothing if check used one of its awk passes.
$PIDLY set 1 due 2026-09-17 >/dev/null
check "an interval expression works, because the matcher is grep" \
	"$(sed -n 's/^due: //p' .pidly/1/info)" "2026-09-17"
out=$($PIDLY set 1 due 17-09-2026 2>&1) && rc=0 || rc=$?
check "and still rejects what it should" "$rc" "1"

echo "empty values"
check "an empty optional field is not matched against its pattern" \
	"$($PIDLY check >/dev/null && echo clean)" "clean"
sed -i 's/^area: cli$/area:/' .pidly/1/info
out=$($PIDLY check 2>&1 || true)
has "an empty required one is a finding" "$out" "1: required field 'area' is empty"
hasnt "about presence, not about the pattern" "$out" "does not match format|cli|docs"
sed -i 's/^area:$/area: cli/' .pidly/1/info

echo "the schema's own faults"
was=$(cat .pidly/schema)
printf '\nfield: broken\nmatch: ^(unclosed\n' >> .pidly/schema
out=$($PIDLY check 2>&1 || true)
has "a pattern grep cannot compile" "$out" "schema: 'broken' has a match grep cannot compile"
hasnt "reported once, not against every ticket" "$out" "1: broken is"
printf '%s\n' "$was" > .pidly/schema

printf '\nfield: pcre\nmatch: \\d+\n' >> .pidly/schema
has "a PCRE escape, whatever the local grep accepts" \
	"$($PIDLY check 2>&1 || true)" "schema: 'pcre' uses a PCRE escape, which is not ERE"
printf '%s\n' "$was" > .pidly/schema

printf '\nrequired: yes\nnote: nobody declared a field\n' >> .pidly/schema
out=$($PIDLY check 2>&1 || true)
has "a stanza with no field:" "$out" "schema: a stanza with no field:"
hasnt "whose keys attach to nothing, not to the stanza above it" \
	"$out" "required field 'handoff'"
printf '%s\n' "$was" > .pidly/schema

printf '\nfield: x\nrequried: yes\n' >> .pidly/schema
has "a misspelled key" "$($PIDLY check 2>&1 || true)" "schema: 'requried:' is not a schema key"
printf '%s\n' "$was" > .pidly/schema

printf '\nfield: y\nrequired: maybe\n' >> .pidly/schema
has "a required: that is neither yes nor no" "$($PIDLY check 2>&1 || true)" \
	"schema: required: takes yes or no"
printf '%s\n' "$was" > .pidly/schema

printf '\nfield: effort\nnote: again\n' >> .pidly/schema
has "a field declared twice" "$($PIDLY check 2>&1 || true)" \
	"schema: 'effort' is declared twice"
printf '%s\n' "$was" > .pidly/schema

check "and the schema is clean again" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "the format's own lines"
# pidly's lines, checked the way a project's fields are. Each one wrong in
# its own way: a key that is not the one that belongs on that line, a value
# the grammar rejects, and a title that is there but empty.
$PIDLY new -f area=cli "structural" </dev/null >/dev/null       # 2
f=.pidly/2/info
sed -i '1s/.*/claim:garbage/' $f
out=$($PIDLY check 2>&1 || true)
has "a claim nothing could parse is a finding" "$out" "2: claim is 'garbage', which is not"
has "shown as the grammar in words, not as the pattern" "$out" "<pid>.<starttime>@<runtime>"
sed -i '1s/.*/claim:/' $f

sed -i '2s/.*/needs: yesterday/' $f
has "a needs that is not numbers" "$($PIDLY check 2>&1 || true)" \
	"2: needs is 'yesterday', which is not ticket numbers separated by spaces"
sed -i '2s/.*/needs: 1/' $f
check "and numbers are fine" "$($PIDLY check >/dev/null && echo clean)" "clean"
sed -i '2s/.*/needs:/' $f

sed -i '3s/.*/title:/' $f
has "a title that is present but empty" "$($PIDLY check 2>&1 || true)" "2: title is empty"
sed -i '3s/.*/nottitle: x/' $f
has "and a line 3 that is not the title at all" "$($PIDLY check 2>&1 || true)" \
	"2: line 3 is not title:"
sed -i '3s/.*/title: structural/' $f

sed -i 's/^created: .*/created: yesterday/' $f
has "a stamp that is not a timestamp" "$($PIDLY check 2>&1 || true)" \
	"2: created is 'yesterday', which is not an ISO-8601 UTC timestamp"
sed -i "s/^created: .*/created: $(sed -n 's/^updated: //p' $f)/" $f
check "and the ticket is clean again" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "a real claim is not a malformed one"
$PIDLY claim 2 >/dev/null
check "a pid claim passes its own grammar" "$($PIDLY check >/dev/null && echo clean)" "clean"
$PIDLY release 2 >/dev/null
PIDLY_LEASE=2h $PIDLY claim 2 >/dev/null
check "so does a pid claim carrying a lease" "$($PIDLY check >/dev/null && echo clean)" "clean"
$PIDLY release 2 >/dev/null
PIDLY_AGENT=cloud-1 PIDLY_LEASE=2h $PIDLY claim 2 >/dev/null
check "and an agent claim with an expiry" "$($PIDLY check >/dev/null && echo clean)" "clean"
sed -i '1s/.*/claim:/' $f

echo "the project cannot weaken them"
printf '\nfield: title\nmatch: .*\n' >> .pidly/schema
sed -i '3s/.*/title:/' $f
out=$($PIDLY check 2>&1 || true)
has "redeclaring one of them is a finding" "$out" \
	"schema: 'title' is the format's own and is not declared here"
has "and the format's rule still applies" "$out" "2: title is empty"
hasnt "while nothing offers to write a second one into the block" \
	"$out" "have no 'title' line"
sed -i '3s/.*/title: structural/' $f
printf '%s\n' "$was" > .pidly/schema

printf '\nline: 4\nfield: effort\n' >> .pidly/schema
has "so is claiming a position" "$($PIDLY check 2>&1 || true)" \
	"schema: line: is the format's own, not a schema key"
printf '%s\n' "$was" > .pidly/schema
check "and the schema is clean once more" "$($PIDLY check >/dev/null && echo clean)" "clean"

echo "the file it replaced"
printf '| field | required | values |\n' > .pidly/schema.md
has "a leftover schema.md is a finding, not silence" "$($PIDLY check 2>&1 || true)" \
	"schema.md is not read any more"
rm .pidly/schema.md

echo "comments and blank lines"
printf '# a trailing comment\n' >> .pidly/schema
check "a comment is not a stanza" "$($PIDLY check >/dev/null && echo clean)" "clean"
check "and the fields are unchanged" \
	"$($PIDLY field effort | tr -s ' ' | tr '\n' '/')" "1 M/2 -/"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
