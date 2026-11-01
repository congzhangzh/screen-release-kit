#!/usr/bin/env bash
# Test a screen binary with ci/repro.py: two attached displays show window 1 and window 1's
# shell exits (Savannah bug #67589). The binary must survive every run; the control binary
# (the same base without our fixes) must crash at least once, or the test proves nothing.
#
# Usage: ci/test.sh <screen binary> [<control binary>]   (runs as a normal user, not root)
set -euo pipefail
here=$(dirname "$(realpath "$0")")
bin=$(realpath "$1")
runs=${RUNS:-10}
work=$(mktemp -d)
echo "== $bin: $runs runs, two displays (must survive all)"
REPRO_DIR=$work python3 -I "$here/repro.py" "$bin" "$runs"
echo "== $bin: 3 runs, one display (must survive all)"
REPRO_CLIENTS=1 REPRO_DIR=$work python3 -I "$here/repro.py" "$bin" 3
if [ -n "${2:-}" ]; then
	echo "== control $2: 3 runs, two displays (must crash at least once)"
	if REPRO_DIR=$work python3 -I "$here/repro.py" "$(realpath "$2")" 3; then
		echo "::error::the control build survived: the test no longer reproduces the bug"
		exit 1
	fi
	echo "control crashed, as it should"
fi
echo "all screen tests passed"
