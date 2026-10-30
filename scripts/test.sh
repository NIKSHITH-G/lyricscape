#!/bin/zsh
# Runs the unit tests. The Command Line Tools' default build system loses track of the
# swift-testing macro plugin on incremental builds, so point the compiler at it explicitly.
set -euo pipefail
cd "${0:A:h}/.."

PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
  exec swift test "$@"
fi
