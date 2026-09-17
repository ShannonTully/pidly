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

echo "the file it replaced"
printf '| field | required | values |\n' > .pidly/schema.md
has "a leftover schema.md is a finding, not silence" "$($PIDLY check 2>&1 || true)" \
	"schema.md is not read any more"
rm .pidly/schema.md

echo "comments and blank lines"
printf '# a trailing comment\n' >> .pidly/schema
check "a comment is not a stanza" "$($PIDLY check >/dev/null && echo clean)" "clean"
check "and the fields are unchanged" \
	"$($PIDLY field effort | tr -s ' ')" "1 M"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
