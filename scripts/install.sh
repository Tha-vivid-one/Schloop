#!/bin/zsh
# Build Schloop in release mode, install the binary to a stable location,
# and (re)install the LaunchAgent so it survives Mac restarts.
#
# Idempotent — re-run any time you want to ship a new version to your own machine.
#
# Usage:
#   ./scripts/install.sh                # build, install, reload agent
#   ./scripts/install.sh --no-restart   # build + install but don't bounce the agent
#
# This script does NOT need sudo. Everything lives under your user directory.

set -euo pipefail

REPO_DIR="${0:A:h:h}"
BINARY_DEST="$HOME/Library/Application Support/Schloop/bin/Schloop"
PLIST_DEST="$HOME/Library/LaunchAgents/com.schloop.app.plist"
PLIST_SOURCE="$REPO_DIR/launchd/com.schloop.app.plist"
LOG_DIR="$HOME/Library/Logs/Schloop"
LOG_OUT="$LOG_DIR/launchd-out.log"
LOG_ERR="$LOG_DIR/launchd-err.log"

LABEL="com.schloop.app"
AGENT_TARGET="gui/$(id -u)/$LABEL"

NO_RESTART=0
for arg in "$@"; do
  case "$arg" in
    --no-restart) NO_RESTART=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

echo "→ Repo:   $REPO_DIR"
echo "→ Binary: $BINARY_DEST"
echo "→ Plist:  $PLIST_DEST"
echo ""

# 1. Build release binary
echo "→ Building release..."
cd "$REPO_DIR"
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build -c release

# 2. Install binary
echo "→ Installing binary..."
mkdir -p "$(dirname "$BINARY_DEST")"
cp "$REPO_DIR/.build/release/Schloop" "$BINARY_DEST"
chmod +x "$BINARY_DEST"

# 3. Install plist (substitute placeholders)
echo "→ Installing LaunchAgent plist..."
mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$PLIST_DEST")"

sed \
  -e "s|__SCHLOOP_BINARY__|$BINARY_DEST|g" \
  -e "s|__SCHLOOP_LOG_OUT__|$LOG_OUT|g" \
  -e "s|__SCHLOOP_LOG_ERR__|$LOG_ERR|g" \
  "$PLIST_SOURCE" > "$PLIST_DEST"

# 4. (Re)load the agent
if [ "$NO_RESTART" = "1" ]; then
  echo ""
  echo "✓ Built + installed. Skipping agent restart (--no-restart)."
  echo "  Run \`launchctl kickstart -k $AGENT_TARGET\` when ready."
  exit 0
fi

echo "→ Bouncing LaunchAgent..."
if launchctl list | grep -q "$LABEL"; then
  launchctl bootout "$AGENT_TARGET" 2>/dev/null || true
fi
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"

sleep 2
if launchctl list | grep -q "$LABEL"; then
  PID=$(launchctl list | awk -v label="$LABEL" '$3 == label { print $1 }')
  echo ""
  echo "✓ Schloop running, PID $PID"
  echo "  Logs:  tail -f $HOME/Library/Logs/Schloop/schloop.log"
  echo "  Stop:  launchctl bootout $AGENT_TARGET"
  echo "  Start: launchctl bootstrap gui/\$(id -u) $PLIST_DEST"
else
  echo ""
  echo "✗ LaunchAgent loaded but Schloop didn't appear in launchctl list."
  echo "  Check:  tail $LOG_ERR"
  exit 1
fi
