#!/usr/bin/env bash
# Build plain upstream screen (no fixes, no Debian patches) as the test's control.
# Usage: ci/build-control.sh <screen repo> <commit> <out binary>
# The -include and -D_GNU_SOURCE work around upstream's build on gcc 16 (openpty needs
# <pty.h>, execvpe needs _GNU_SOURCE); configure runs without them, because the -include
# breaks its openpty probe.
set -euo pipefail
repo=$(realpath "$1") commit=$2 out=$(realpath -m "$3")
work=$(mktemp -d)
git -C "$repo" archive --format=tar "$commit:src" | tar -x -C "$work"
cd "$work"
./autogen.sh >/dev/null
./configure -q --enable-socket-dir=/run/screen --enable-colors256 --enable-use-locale --disable-utmp CFLAGS="-g -O2"
make -s -j"$(nproc)" CFLAGS="-g -O2 -D_GNU_SOURCE -include /usr/include/pty.h -std=gnu17 -w"
mkdir -p "$(dirname "$out")"
cp screen "$out"
echo "control: $(git -C "$repo" rev-parse --short "$commit") -> $out"
