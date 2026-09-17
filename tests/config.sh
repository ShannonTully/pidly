# Sourced by every suite. Holds knobs that depend on the machine rather than
# on pidly, so a constrained environment can turn them down without editing
# the tests.
#
# Precedence: an exported variable wins, then .env at the repo root, then the
# default here. .env is gitignored — it describes one machine, not the
# project.

# Find the repo root by walking up for bin/pidly. Not from $0: this file is
# sourced, so $0 belongs to the caller and may already have been cd'd away
# from — which silently gave run.sh a different answer than the suites it
# runs.
_cfg_root=$PWD
while [ "$_cfg_root" != / ] && [ ! -x "$_cfg_root/bin/pidly" ]; do
	_cfg_root=$(dirname "$_cfg_root")
done

if [ -f "$_cfg_root/.env" ]; then
	while IFS= read -r _cfg_line || [ -n "$_cfg_line" ]; do
		case $_cfg_line in
		''|\#*) continue ;;
		esac
		_cfg_k=${_cfg_line%%=*}
		_cfg_v=${_cfg_line#*=}
		case $_cfg_k in
		*[!A-Za-z0-9_]*|'') continue ;;   # ignore anything that isn't a name
		esac
		# An already-exported value wins, so PIDLY_TEST_RACE=40 ./tests/run.sh
		# overrides the file.
		eval "[ -n \"\${$_cfg_k:-}\" ] || export $_cfg_k=\"\$_cfg_v\""
	done < "$_cfg_root/.env"
fi

# How many processes race each other in the concurrency tests. Higher is a
# better test of the locking; some sandboxes cannot fork that widely.
: "${PIDLY_TEST_RACE:=32}"
