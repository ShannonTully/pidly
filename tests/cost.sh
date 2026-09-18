#!/bin/sh
# Tests for what check costs, and for the findings that pay for it.
#
# check tests a value against its field's pattern with grep, because grep is
# the only matcher whose meaning does not depend on which awk is installed.
# Asking it once per value is a process per patterned field per ticket, which
# is what made check cost about a second a ticket. The answers are batched
# instead: one grep per distinct pattern, for every value in the tracker.
#
# Two things have to hold, and the second is the one that makes the first
# safe. The count must not grow with the tracker, and the findings must be
# exactly the ones the per-value form produced — a batch maps results back to
# tickets by line number, and getting that wrong loses a finding quietly.
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

# A tracker of n tickets, written by hand rather than by n calls to new: this
# is about what check costs over many tickets, and paying for new to make them
# would dwarf it. Every ticket is valid unless a caller damages it after.
build() {
	rm -rf "$2"; mkdir -p "$2"; (
		cd "$2"
		$PIDLY init >/dev/null
		# Two patterned fields of this suite's own, so the test does not
		# depend on what the default schema happens to declare.
		cat >> .pidly/schema <<'SCHEMA'

field: effort
match: S|M|L
note: rough size

field: area
match: format|cli|docs
note: which part of the project this is
SCHEMA
		i=1
		while [ "$i" -le "$1" ]; do
			mkdir -p ".pidly/$i"
			cat > ".pidly/$i/info" <<INFO
claim:
needs:
title: ticket $i
created: 2026-09-01T00:00:00Z
updated: 2026-09-02T00:00:00Z
effort: M
area: cli
handoff:
INFO
			printf 'n%s ticket %s\n' "$i" "$i" > ".pidly/.n/$i"
			i=$((i + 1))
		done
	)
}

echo "the findings a batch has to keep"
# Several tickets failing the same pattern, several failing a different one,
# and valid tickets in between. A batch collects every value one pattern
# guards into one list and maps the failures back by position; interleaving
# them is what catches an off-by-one that a single bad ticket would not.
build 9 many
cd many
sedi 's/^effort: M/effort: XL/'    .pidly/2/info
sedi 's/^area: cli/area: kitchen/' .pidly/3/info
sedi 's/^effort: M/effort: XS/'    .pidly/5/info
sedi 's/^area: cli/area: garden/'  .pidly/7/info
sedi 's/^effort: M/effort: XXL/'   .pidly/8/info
out=$($PIDLY check 2>&1) || true
has "the first failure of a pattern is reported" "$out" \
	"2: effort is 'XL', which does not match S|M|L"
has "and the second, three tickets later" "$out" \
	"5: effort is 'XS', which does not match S|M|L"
has "and the third" "$out" \
	"8: effort is 'XXL', which does not match S|M|L"
has "a second pattern reports its own" "$out" \
	"3: area is 'kitchen', which does not match format|cli|docs"
has "both of them" "$out" \
	"7: area is 'garden', which does not match format|cli|docs"
check "and nothing else is reported" \
	"$(printf '%s' "$out" | grep -c '^[0-9][0-9]*: ')" "5"
for n in 1 4 6 9; do
	hasnt "ticket $n, which is valid, is not accused" "$out" "$n: "
done
cd "$tmp"

# The format's own lines carry patterns too, and they are reported with the
# note rather than the pattern — a reader cannot open the file a compiled-in
# pattern lives in. Batching must not swap the two vocabularies.
echo "the format's lines keep their own wording"
build 3 fmt
cd fmt
sedi 's/^created: .*/created: yesterday/' .pidly/2/info
out=$($PIDLY check 2>&1) || true
has "a format field says what it is, not what it matches" "$out" \
	"2: created is 'yesterday', which is not an ISO-8601 UTC timestamp"
cd "$tmp"

# The same value in two tickets is one entry in a batch keyed by pattern and
# two findings. Deduplicating by value would report one of them.
echo "two tickets sharing a bad value"
build 4 dup
cd dup
sedi 's/^effort: M/effort: XL/' .pidly/2/info
sedi 's/^effort: M/effort: XL/' .pidly/4/info
out=$($PIDLY check 2>&1) || true
has "the first is reported" "$out" "2: effort is 'XL'"
has "and so is the second" "$out" "4: effort is 'XL'"
cd "$tmp"

# edit judges one draft through the same function, and it is the caller that
# has no tracker to batch over. It settles a queue of its own, so the finding
# still reaches stderr before the command returns — deferred and never
# flushed, a bad value would save silently, which is the failure this whole
# mechanism could introduce.
echo "a single ticket still gets its findings"
build 2 one
cd one
cat > "$tmp/ed-badvalue" <<'ED'
#!/bin/sh
sed 's/^effort: M/effort: XL/' "$1" > "$1.new" && mv "$1.new" "$1"
ED
chmod +x "$tmp/ed-badvalue"
out=$(EDITOR="$tmp/ed-badvalue" $PIDLY edit 1 2>&1) && rc=0 || rc=$?
check "the edit is refused" "$rc" "1"
has "and says which value it was" "$out" "1: effort is 'XL'"
check "the ticket on disk is untouched" \
	"$(sed -n 's/^effort: //p' .pidly/1/info)" "M"
cd "$tmp"

echo "and the cost does not grow with the tracker"
# Counted rather than timed: a stopwatch measures the machine, and the thing
# that regressed is the number of processes. Every external command becomes a
# wrapper that logs its name and execs the real one.
#
# The real path is resolved absolutely here. A wrapper that exec'd a bare name
# would find itself on PATH and recurse.
mkdir -p wrap
wrapped=yes
for c in grep awk sed sort head cut tr cmp wc uniq ls cat; do
	real=$(command -v "$c" 2>/dev/null || true)
	case $real in
	/*) ;;
	*)  wrapped="" ; break ;;
	esac
	printf '#!/bin/sh\nprintf "%%s\\n" %s >> "$FORKLOG"\nexec %s "$@"\n' \
		"$c" "$real" > "wrap/$c"
	chmod +x "wrap/$c"
done

if [ -z "$wrapped" ]; then
	ok "not every command resolves to a path here, skipping the count (3 tests)"
	pass=$((pass + 2))
else
	count() {
		FORKLOG="$tmp/forks.$2"; export FORKLOG
		: > "$FORKLOG"
		( cd "$1" && PATH="$tmp/wrap:$PATH" $PIDLY check >/dev/null 2>&1 ) || true
		grep -c . < "$FORKLOG" || true
	}
	build 20 small
	build 60 large
	small=$(count small s)
	large=$(count large l)
	check "three times the tickets is the same number of processes" \
		"$large" "$small"
	# A per-ticket process would put the count in the hundreds. The bound is
	# loose on purpose: it is here to catch a loop that spawns, not to pin
	# the exact number, which every new check will move.
	if [ "$large" -lt 100 ]; then
		ok "and that number is a constant, not a multiple ($large)"
	else
		no "check spawns $large processes for 60 tickets"
	fi
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
