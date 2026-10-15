#!/bin/sh
# Reads the ambience-sync settings and the current ambience, then applies (or
# resets) the Android system color and, optionally, the Android dark/light
# theme inside AppSupport.
# Runs as root. Pass --reset to restore Android's previous settings.

USER_HOME="/home/defaultuser"
STATE_DIR="/var/lib/ambience-sync"
STATE="$STATE_DIR/applied"
# exists while we control Android's night mode; holds the mode it had before
# (auto, yes or no)
NIGHT_PREV="$STATE_DIR/night_mode_prev"
ANDROID_KEY="theme_customization_overlay_packages"

# dconf reads the current user's database, so point root at defaultuser's
export XDG_CONFIG_HOME="$USER_HOME/.config"

read_conf() {
    dconf read "$1" 2>/dev/null | tr -d "'"
}

reset_android() {
    # only touch Android if we were the ones who set the theme
    if [ -e "$STATE" ]; then
        appsupport-attach /system/bin/settings delete secure "$ANDROID_KEY" >/dev/null 2>&1 \
            && rm -f "$STATE"
    fi
}

# Put Android's night mode back to what it was before we first changed it.
# If Android can't be reached, the marker stays and a later run retries.
reset_night() {
    [ -e "$NIGHT_PREV" ] || return 0
    PREV=$(cat "$NIGHT_PREV")
    # markers from earlier versions held the raw ui_night_mode number
    case "$PREV" in
        null|0|3) PREV="auto" ;;
        1) PREV="no" ;;
        2) PREV="yes" ;;
    esac
    case "$PREV" in
        auto|yes|no|custom_schedule|custom_bedtime) ;;
        *) rm -f "$NIGHT_PREV"; return 0 ;;   # unreadable marker, nothing to restore
    esac
    appsupport-attach /system/bin/cmd uimode night "$PREV" >/dev/null 2>&1 \
        && rm -f "$NIGHT_PREV"
}

if [ "$1" = "--reset" ]; then
    reset_android
    reset_night
    exit 0
fi

# unset counts as off
ENABLED=$(read_conf /desktop/ambience-sync/enabled)
MONOCHROME=$(read_conf /desktop/ambience-sync/monochrome)
FOLLOW=$(read_conf /desktop/ambience-sync/follow_dark_mode)

# Sets (or resets) the Android system color from the highlight color
apply_color() {
    if [ "$ENABLED" != "true" ] && [ "$MONOCHROME" != "true" ]; then
        reset_android
        return 0
    fi

    # Monochrome ignores color, so the highlight color isn't read in that case
    if [ "$MONOCHROME" != "true" ]; then
        # dconf returns the value in quotes, e.g. '#ff80ffab'; read_conf strips them
        COLOR=$(read_conf /desktop/jolla/theme/color/highlight)

        if ! printf '%s' "$COLOR" | grep -Eq '^#[0-9a-fA-F]{8}$'; then
            echo "Could not read highlight color from dconf" >&2
            return 1
        fi
    fi

    # the settings page stores the style as an index (same order as its menu);
    # the value is user-writable, so anything unknown falls back to TONAL_SPOT.
    # The Monochrome switch overrides the selection.
    STYLE_INDEX=$(read_conf /desktop/ambience-sync/style_index)
    case "$STYLE_INDEX" in
        0) STYLE="TONAL_SPOT" ;;
        1) STYLE="VIBRANT" ;;
        2) STYLE="RAINBOW" ;;
        *) STYLE="TONAL_SPOT" ;;
    esac
    if [ "$MONOCHROME" = "true" ]; then
        STYLE="MONOCHROMATIC"
    fi

    if [ "$MONOCHROME" = "true" ]; then
        RGB="808080"    # neutral seed; the monochrome style ignores it
    else
        # #AARRGGBB -> RRGGBB (drop the alpha pair)
        RGB=$(printf '%s' "$COLOR" | sed 's/^#..//')
    fi

    JSON="{\"android.theme.customization.system_palette\":\"#$RGB\",\"android.theme.customization.color_source\":\"preset\",\"android.theme.customization.theme_style\":\"$STYLE\"}"

    if appsupport-attach /system/bin/settings put secure "$ANDROID_KEY" "$JSON" >/dev/null 2>&1; then
        mkdir -p "$STATE_DIR"
        : > "$STATE"
    fi
}

# Matches Android's dark/light theme to Sailfish's color scheme
# (Sailfish 0 = dark, 1 = light). This uses the uimode service because Android
# doesn't pick up a plain change of the ui_night_mode setting.
apply_night() {
    SCHEME=$(read_conf /desktop/jolla/theme/color_scheme)
    case "$SCHEME" in
        0) NIGHT="yes" ;;
        1) NIGHT="no" ;;
        *)
            echo "Could not read color scheme from dconf" >&2
            return 1
            ;;
    esac

    # remember Android's current mode, once, before the first change
    if [ ! -e "$NIGHT_PREV" ]; then
        # prints e.g. "Night mode: auto"; the mode is the last word
        PREV=$(appsupport-attach /system/bin/cmd uimode night 2>/dev/null \
            | tr -d '\r' | awk 'NF { w = $NF } END { print w }')
        # anything else means Android couldn't be reached: change nothing and
        # retry on the next run
        case "$PREV" in
            auto|yes|no|custom_schedule|custom_bedtime) ;;
            *) return 1 ;;
        esac
        mkdir -p "$STATE_DIR"
        printf '%s\n' "$PREV" > "$NIGHT_PREV"
    fi

    appsupport-attach /system/bin/cmd uimode night "$NIGHT" >/dev/null 2>&1
}

# An ambience change only matters for the color while "Sync ambience color" is
# on (and Monochrome off), and for the theme while "Follow light/dark theme"
# is on. Otherwise there is nothing to update.
RUN_COLOR=true
if [ "$1" = "--ambience-changed" ]; then
    if [ "$ENABLED" != "true" ] || [ "$MONOCHROME" = "true" ]; then
        RUN_COLOR=false
    fi
    if [ "$RUN_COLOR" = "false" ] && [ "$FOLLOW" != "true" ]; then
        exit 0
    fi
fi

if [ "$RUN_COLOR" = "true" ]; then
    apply_color
fi

if [ "$FOLLOW" = "true" ]; then
    apply_night
else
    reset_night
fi
