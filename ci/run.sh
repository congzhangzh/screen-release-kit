#!/usr/bin/env bash
# The whole pipeline for one commit, in a Debian container (as root): install the build
# dependencies, build the .deb and the tarball, build the unfixed control, run the tests as
# a normal user. The kit workflow runs exactly this; so can a local podman run.
#
# Usage: ci/run.sh <screen repo> <commit> <control commit | -> <package version> <out dir>
#   "-" as the control skips it (once upstream has the fix, there is nothing to reproduce).
set -euo pipefail
here=$(dirname "$(realpath "$0")")
repo=$1 commit=$2 control=$3 version=$4 out=$(realpath -m "$5")

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends build-essential debhelper dpkg-dev \
	libcrypt-dev libncurses-dev libpam0g-dev texinfo autoconf automake git python3 \
	ca-certificates > /dev/null
git config --global --add safe.directory '*'

"$here/build.sh" "$repo" "$commit" "$version" "$out"
control_bin=''
if [ "$control" != - ]; then
	"$here/build-control.sh" "$repo" "$control" "$out/control/screen"
	control_bin=$out/control/screen
fi

id tester > /dev/null 2>&1 || useradd -m tester
chmod -R a+rX "$out"
# The kit may be read-only (a podman :ro mount); then it must already be readable.
chmod -R a+rX "$here" 2>/dev/null || true
runuser -u tester -- "$here/test.sh" "$out/screen.bin" ${control_bin:+"$control_bin"} 2>&1 | tee "$out/test.log"
