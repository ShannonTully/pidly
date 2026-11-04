#!/bin/sh
# Run every suite. Exits nonzero if any of them fail.
set -eu
cd "$(dirname "$0")"
. ./config.sh
printf 'concurrency tests use %s processes' "$PIDLY_TEST_RACE"
[ -f ../.env ] && printf ' (from .env)'
printf '; override with PIDLY_TEST_RACE\n'
rc=0
# Every *.sh here is a suite except this runner and the two files the suites
# source. Found rather than listed, so a new suite cannot be skipped by
# forgetting to add it here (68).
for t in *.sh; do
	case $t in run.sh | lib.sh | config.sh) continue ;; esac
	printf '\n=== %s ===\n' "$t"
	./"$t" || rc=1
done
printf '\n'
[ "$rc" -eq 0 ] && echo "all suites passed" || echo "SOME SUITES FAILED"
exit "$rc"
