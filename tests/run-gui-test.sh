#!/bin/sh
#
# Headless smoke test: launches the real maha binary under Xvfb, sends Ctrl+S,
# Ctrl+N and the font-zoom shortcuts through the shortcut controller, and fails
# if the process dies. This guards the shortcut-controller lifetime and the
# runtime zoom's CSS provider reload, which are pure GTK and not covered by the
# core unit tests.
#
# Skips (exit 77) when the required tooling (Xvfb, xdotool, dbus-run-session)
# is unavailable.

BIN="$1"
# Pick a display from the shell PID to reduce collisions between runs, and
# clear any stale lock/socket so Xvfb can always start.
DISPLAY_NUM=":$((90 + ($$ % 8)))"
XVFB_PID=""
APP_PID=""
CONFIG_DIR=""
LOG="$(mktemp)"

cleanup() {
    # APP_PID is a process-group leader (started with setsid), so kill the group.
    if [ -n "$APP_PID" ]; then
        kill -TERM -"$APP_PID" 2>/dev/null || kill -TERM "$APP_PID" 2>/dev/null
    fi
    [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2>/dev/null
    [ -n "$CONFIG_DIR" ] && rm -rf "$CONFIG_DIR"
    [ -n "$LOG" ] && rm -f "$LOG"
}

for tool in Xvfb xdotool dbus-run-session; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "SKIP: $tool not installed"
        exit 77
    fi
done

trap cleanup EXIT INT TERM

# Isolate any config/session writes from the user's real environment.
CONFIG_DIR="$(mktemp -d)"
export XDG_CONFIG_HOME="$CONFIG_DIR"

# Open a real file (via a legacy raw-path session) so Ctrl+S saves in place
# instead of opening the "save as" dialog.
mkdir -p "$CONFIG_DIR/maha"
NOTE="$CONFIG_DIR/note.txt"
printf 'hello\n' >"$NOTE"
printf '%s\n' "$NOTE" >"$CONFIG_DIR/maha/session"

X_NUM="${DISPLAY_NUM#:}"
rm -f "/tmp/.X${X_NUM}-lock" "/tmp/.X11-unix/X${X_NUM}" 2>/dev/null

Xvfb "$DISPLAY_NUM" -screen 0 1024x768x24 >/dev/null 2>&1 &
XVFB_PID=$!
sleep 1

export DISPLAY="$DISPLAY_NUM"
export LIBGL_ALWAYS_SOFTWARE=1
export GSK_RENDERER=cairo

# setsid puts the whole app tree (dbus-run-session + maha) in its own process
# group so cleanup can tear it all down at once.
if command -v setsid >/dev/null 2>&1; then
    setsid dbus-run-session -- "$BIN" >"$LOG" 2>&1 &
else
    dbus-run-session -- "$BIN" >"$LOG" 2>&1 &
fi
APP_PID=$!

WID=""
i=0
while [ "$i" -lt 20 ]; do
    WID="$(xdotool search --name "maha" 2>/dev/null | head -1)"
    [ -n "$WID" ] && break
    i=$((i + 1))
    sleep 0.5
done

if [ -z "$WID" ]; then
    echo "FAIL: maha window never appeared"
    cat "$LOG"
    exit 1
fi

xdotool mousemove 400 300 click 1
sleep 1
xdotool key ctrl+s
sleep 1
# New-tab alias, line duplication and runtime font zoom (app-wide, not
# persisted): all must be crash-free.
xdotool key ctrl+n
sleep 0.5
xdotool key ctrl+d
sleep 0.5
xdotool key ctrl+plus
sleep 0.5
xdotool key ctrl+minus
sleep 0.5
xdotool key ctrl+0
sleep 2

if kill -0 "$APP_PID" 2>/dev/null; then
    echo "PASS: maha survived Ctrl+S, Ctrl+N, Ctrl+D and font zoom"
    exit 0
fi

wait "$APP_PID"
STATUS=$?
echo "FAIL: maha died after keyboard exercise (status $STATUS)"
echo "--- application output ---"
cat "$LOG"
exit 1
