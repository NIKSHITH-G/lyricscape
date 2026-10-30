#!/bin/zsh
# Builds, (re)launches Lyricscape and streams its log to this terminal. Ctrl-C stops the log (the app keeps running).
# Usage: scripts/run.sh [debug|release]
set -euo pipefail
cd "${0:A:h}/.."

scripts/build-app.sh "${1:-debug}"
pkill -x Lyricscape 2>/dev/null && sleep 0.5 || true

# Launch through LaunchServices (not by running the binary directly) so macOS
# attributes the Automation permission to Lyricscape rather than to your terminal.
open build/Lyricscape.app
echo "Streaming logs (Ctrl-C to stop)…"
exec /usr/bin/log stream --style compact --level info --predicate 'subsystem == "app.lyricscape"'
