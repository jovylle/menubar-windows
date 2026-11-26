#!/bin/sh
# Captures the screenshots in assets/screenshots/ from the real app in demo mode.
#
#   swift build -c release && ./scripts/capture-screenshots.sh            # every shot
#   ./scripts/capture-screenshots.sh context-menu.png order-picker.png      # only these
#
# It builds nothing except its own small helper (scripts/screenshot-tool.swift, compiled into .build/).
# For each shot it launches .build/release/MenubarWindows with demo flags, waits, captures ONLY that
# process's own windows with `screencapture -l <windowID> -o` (no shadow, never the whole screen), then
# quits that process. Window IDs come from CGWindowList filtered by the launched process ID, so another
# running copy of the app (with real windows) is never captured.
#
# Demo mode shows invented windows and displays and uses a throwaway settings suite, so the user's real
# settings are not changed. Each launch shows the strip (and for Settings shots, the Settings window) for
# about three seconds. Set MW_BINARY to capture another build, for example the .app executable.
#
# Gotchas:
# - Clicking anywhere while a shot runs can close the demo menu or keep Settings from becoming active.
#   Menu shots and window shots retry; a window shot that never became active is reported at the end.
# - The hero images need strip-light.png, strip-black.png and both menu captures, plus the menu offsets
#   saved in .build/ by the menu shots. They are composed again whenever those inputs exist.
set -eu
cd "$(dirname "$0")/.."

BIN="${MW_BINARY:-.build/release/MenubarWindows}"
OUT="assets/screenshots"
TOOL=".build/screenshot-tool"
WAIT="${MW_WAIT:-2.5}"
TMP="$(mktemp -d)"
PID=""
INACTIVE=""
ONLY="$*"

[ -x "$BIN" ] || { echo "Missing $BIN. Run: swift build -c release" >&2; exit 1; }
mkdir -p "$OUT"
if [ ! -x "$TOOL" ] || [ scripts/screenshot-tool.swift -nt "$TOOL" ]; then
    swiftc -O scripts/screenshot-tool.swift -o "$TOOL"
fi

cleanup() {
    if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; fi
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

# Strip shots: left placement and a wide maximum give the strip all the room left of a notch.
COMMON="-mw.demo YES -mw.demoBackdrop YES -mw.hideInFullScreen NO -mw.placement left -mw.stripWidth 900"

wanted() { # <file>: true when no names were given or the file is one of them
    [ -z "$ONLY" ] && return 0
    for name in $ONLY; do [ "$name" = "$1" ] && return 0; done
    return 1
}

launch() {
    # shellcheck disable=SC2086
    "$BIN" $COMMON "$@" >/dev/null 2>&1 &
    PID=$!
    sleep "$WAIT"
    kill -0 "$PID" 2>/dev/null || { echo "The app exited early" >&2; exit 1; }
}

quit() {
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    PID=""
}

# Prints "id x y width height" (points, top-left origin) of the launched process's first window on
# that layer, optionally with that exact title.
find_window() {
    "$TOOL" windows "$PID" | awk -v layer="$1" -v name="${2:-}" '
        $2 == layer {
            title = ""; for (i = 7; i <= NF; i++) title = title (i > 7 ? " " : "") $i
            if (name == "" || title == name) { print $1, $3, $4, $5, $6; exit }
        }'
}

grab() { # <window id> <file>
    screencapture -x -o -l "$1" "$2"
}

strip_shot() { # <file> <launch args...>
    file="$1"; shift
    wanted "$file" || return 0
    launch "$@"
    id=$(find_window 101 | awk '{print $1}')
    [ -n "$id" ] || { echo "No strip window for $file" >&2; exit 1; }
    # Kept at the panel's full size: the top 6pt are the click overscan above the screen edge.
    grab "$id" "$OUT/$file"
    quit
    echo "captured $OUT/$file"
}

menu_shot() { # <file> <offset name> <combined file or ""> <launch args...>
    file="$1"; offsets=".build/screenshot-offset-$2"; combined="$3"; shift 3
    wanted "$file" || return 0
    # Any click elsewhere closes an open menu, so try up to three times.
    menu=""
    for attempt in 1 2 3; do
        launch -mw.demoMenu 1 "$@"
        sleep 1
        strip=$(find_window 101)
        menu=$("$TOOL" windows "$PID" | awk '$2 >= 101 && $6 > 60 { print $1, $3, $4, $5, $6; exit }')
        if [ -n "$menu" ]; then
            sleep 1   # let the menu finish fading in
            if "$TOOL" windows "$PID" | awk -v id="${menu%% *}" '$1 == id { found = 1 } END { exit !found }'; then
                break
            fi
            menu=""
        fi
        quit
    done
    [ -n "$menu" ] || { echo "No menu window for $file" >&2; exit 1; }
    set -- $menu
    # A window capture of an open menu also contains the strip it belongs to (both are this app's
    # windows), so the capture spans both. Crop the menu out of it at 2x.
    grab "$1" "$TMP/raw.png"
    sx=$(echo "$strip" | awk '{print $2}'); sy=$(echo "$strip" | awk '{print $3}')
    ox=$(( sx < $2 ? sx : $2 )); oy=$(( sy < $3 ? sy : $3 ))
    "$TOOL" crop "$TMP/raw.png" "$OUT/$file" $(( ($2 - ox) * 2 )) $(( ($3 - oy) * 2 )) $(( $4 * 2 )) $(( $5 * 2 ))
    if [ -n "$combined" ]; then cp "$TMP/raw.png" "$OUT/$combined"; fi
    # Menu left edge minus strip left edge, in points, for the hero composition.
    echo $(( $2 - sx )) > "$offsets"
    quit
    echo "captured $OUT/$file"
}

window_shot() { # <file> <window title> <launch args...>
    file="$1"; title="$2"; shift 2
    wanted "$file" || return 0
    # macOS 14+ may refuse to bring an accessory app forward, and an inactive window draws grey
    # traffic lights. Retry until the close button (16, 16 pt) is red, at most five times.
    red=0
    for attempt in 1 2 3 4 5; do
        launch "$@"
        id=$(find_window 0 "$title" | awk '{print $1}')
        [ -n "$id" ] || { echo "No window \"$title\" for $file" >&2; exit 1; }
        grab "$id" "$TMP/window.png"
        quit
        red=$("$TOOL" pixel "$TMP/window.png" 32 32 | awk '{print ($1 > 200 && $2 < 140) ? 1 : 0}')
        [ "$red" = 1 ] && break
        echo "  $file: window was not active, retrying" >&2
    done
    [ "$red" = 1 ] || INACTIVE="$INACTIVE $file"
    cp "$TMP/window.png" "$OUT/$file"
    echo "captured $OUT/$file"
}

LIGHT="-mw.debugAppearance light"
SIX="-mw.equalTabWidth NO -mw.label appName"
SETTINGS="MenubarWindows Settings"

strip_shot strip-light.png   $LIGHT $SIX
strip_shot strip-black.png   $LIGHT $SIX -mw.colorTheme black
strip_shot strip-compact.png $LIGHT -mw.demoCount 8 -mw.demoActive 2
strip_shot strip-three.png   $LIGHT -mw.demoCount 3

menu_shot context-menu.png      light strip-menu.png $LIGHT $SIX
menu_shot context-menu-dark.png dark  ""             -mw.debugAppearance dark $SIX -mw.colorTheme black

window_shot settings-appearance.png "$SETTINGS" $LIGHT -mw.openSettings YES -mw.settingsPane appearance
window_shot settings-tabs.png       "$SETTINGS" $LIGHT -mw.openSettings YES -mw.settingsPane tabs -mw.pinnedApps '(demo.planner)'
window_shot settings-displays.png   "$SETTINGS" $LIGHT -mw.openSettings YES -mw.settingsPane displays -mw.showOnAllDisplays NO
window_shot settings-behaviour.png  "$SETTINGS" $LIGHT -mw.openSettings YES -mw.settingsPane behaviour
window_shot settings-general.png    "$SETTINGS" $LIGHT -mw.openSettings YES -mw.settingsPane general
window_shot settings-about.png      "$SETTINGS" $LIGHT -mw.openSettings YES -mw.settingsPane about
window_shot onboarding.png "Welcome to MenubarWindows" $LIGHT -mw.showOnboarding YES

# The order picker: the top of the Tabs and order pane (preview and the Order section), with a
# different order selected than in settings-tabs.png.
if wanted order-picker.png; then
    ONLY_SAVED="$ONLY"; ONLY=""
    window_shot settings-order.png "$SETTINGS" $LIGHT -mw.openSettings YES -mw.settingsPane tabs -mw.order recentFirst
    ONLY="$ONLY_SAVED"
    W=$(sips -g pixelWidth "$OUT/settings-order.png" | awk '/pixelWidth/ {print $2}')
    "$TOOL" crop "$OUT/settings-order.png" "$OUT/order-picker.png" 0 0 "$W" "${MW_ORDER_CROP:-940}"
    rm -f "$OUT/settings-order.png"
    INACTIVE=$(echo "$INACTIVE" | sed 's/settings-order.png/order-picker.png/')
    echo "cropped $OUT/order-picker.png"
fi

# Heroes: the real strip and menu captures on a drawn menu bar. Tab height in points is the strip
# capture's height at 2x minus the 6pt overscan.
if [ -f "$OUT/strip-light.png" ] && [ -f "$OUT/context-menu.png" ] && [ -f .build/screenshot-offset-light ] \
    && [ -f "$OUT/strip-black.png" ] && [ -f "$OUT/context-menu-dark.png" ] && [ -f .build/screenshot-offset-dark ]; then
    H=$(sips -g pixelHeight "$OUT/strip-light.png" | awk '/pixelHeight/ {print $2}')
    TAB=$(( H / 2 - 6 ))
    "$TOOL" hero "$OUT/strip-light.png" "$OUT/context-menu.png" "$OUT/hero.png" light "$(cat .build/screenshot-offset-light)" "$TAB"
    "$TOOL" hero "$OUT/strip-black.png" "$OUT/context-menu-dark.png" "$OUT/hero-black.png" black "$(cat .build/screenshot-offset-dark)" "$TAB"
    echo "composed $OUT/hero.png and $OUT/hero-black.png"
    "$TOOL" notch "$OUT/strip-light.png" "$OUT/hero-notch.png" light "$TAB"
    "$TOOL" notch "$OUT/strip-black.png" "$OUT/hero-notch-black.png" black "$TAB"
    echo "composed $OUT/hero-notch.png and $OUT/hero-notch-black.png"
    # The landing page uses four of them, referenced locally.
    cp "$OUT/hero.png" "$OUT/hero-black.png" "$OUT/hero-notch.png" "$OUT/settings-tabs.png" "$OUT/strip-compact.png" site/assets/
    echo "copied five screenshots to site/assets/"
fi

for f in "$OUT"/*.png; do
    printf '%-42s %8s bytes  %s\n' "$f" "$(stat -f %z "$f")" \
        "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/ {printf "%s ", $2}')"
done
if [ -n "$INACTIVE" ]; then
    echo "Not active after five tries (grey window controls):$INACTIVE. Re-run with those names." >&2
fi
echo "Look at every image before committing it."
