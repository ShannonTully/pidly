#!/bin/sh
# Run every suite. Exits nonzero if any of them fail.
set -eu
cd "$(dirname "$0")"
. ./config.sh
printf 'concurrency tests use %s processes' "$PIDLY_TEST_RACE"
[ -f ../.env ] && printf ' (from .env)'
printf '; override with PIDLY_TEST_RACE\n'
rc=0
for t in init.sh new.sh merge.sh claim.sh handoff.sh identity.sh close.sh views.sh agents.sh; do
	printf '\n=== %s ===\n' "$t"
	./"$t" || rc=1
done
printf '\n'
[ "$rc" -eq 0 ] && echo "all suites passed" || echo "SOME SUITES FAILED"
exit "$rc"
