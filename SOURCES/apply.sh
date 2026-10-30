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
# exists while we control Android's font scale; holds the value it had before
FONT_PREV="$STATE_DIR/font_scale_prev"
ANDROID_KEY="theme_customization_overlay_packages"
# exists while we control Android's dark surface colors (pure black)
BLACK_STATE="$STATE_DIR/pure_black"
# Pure black is a set of fabricated overlays, one per dark surface color of the
# Android framework. They all share the prefix pb_, so they can be found again
# and switched off.
BLACK_PKG="com.android.shell"
# Pure black has two levels. The base level makes only the base layer black
# (backgrounds), so cards and other raised surfaces keep Android's dark gray and
# stay visible on top of it. The extra level ("Black cards and surfaces") makes
# those black as well, so everything blends together. To move a color between the
# levels, move its name ("system_<role>_dark") between the two lists. Overlays of
# ours that are no longer wanted are switched off automatically.
BLACK_BASE="system_background_dark system_surface_dark system_surface_dim_dark
system_surface_container_lowest_dark"
BLACK_EXTRA="system_surface_container_low_dark system_surface_container_dark
system_surface_container_high_dark system_surface_container_highest_dark
system_surface_bright_dark system_surface_variant_dark"
# what is applied right now; set from the settings below
BLACK_RES="$BLACK_BASE"
BLACK_COUNT=0
# set to 1 whenever we change Android's color setting: Android then registers its
# own color overlays again (see apply_black)
COLOR_TOUCHED=0

# dconf reads the current user's database, so point root at defaultuser's
export XDG_CONFIG_HOME="$USER_HOME/.config"

read_conf() {
    dconf read "$1" 2>/dev/null | tr -d "'"
}

reset_android() {
    # only touch Android if we were the ones who set the theme
    if [ -e "$STATE" ]; then
        COLOR_TOUCHED=1
        # Android keeps the last theme style when the setting is simply deleted,
        # so hand it a plain default first, then remove the setting
        appsupport-attach /system/bin/settings put secure "$ANDROID_KEY" '{"android.theme.customization.color_source":"home_wallpaper","android.theme.customization.theme_style":"TONAL_SPOT"}' >/dev/null 2>&1
        sleep 3
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

# Put Android's font scale back to what it was before we first changed it.
# If Android can't be reached, the marker stays and a later run retries.
reset_font() {
    [ -e "$FONT_PREV" ] || return 0
    FPREV=$(cat "$FONT_PREV")
    # it was never set, which means Android's default
    [ "$FPREV" = "null" ] && FPREV="1.0"
    if ! printf '%s' "$FPREV" | grep -Eq '^[0-9](\.[0-9]{1,3})?$'; then
        rm -f "$FONT_PREV"; return 0   # unreadable marker, nothing to restore
    fi
    appsupport-attach /system/bin/settings put system font_scale "$FPREV" >/dev/null 2>&1 \
        && rm -f "$FONT_PREV"
}

# Switch the pure black overlays off again (Android then uses its normal dark
# colors). If Android can't be reached, the marker stays and a later run retries.
reset_black() {
    [ -e "$BLACK_STATE" ] || return 0
    LIST=$(appsupport-attach /system/bin/cmd overlay list 2>/dev/null) || return 1
    LIST=$(printf '%s\n' "$LIST" | tr -d '\r')
    # an empty list means Android could not be asked, not that nothing is on
    printf '%s\n' "$LIST" | grep -Eq '^\[.\] ' || return 1
    FAIL=0
    for o in $(printf '%s\n' "$LIST" | grep -o "^\[x\] $BLACK_PKG:pb_[A-Za-z0-9_]*" | sed 's/^\[x\] //'); do
        appsupport-attach /system/bin/cmd overlay disable --user 0 "$o" >/dev/null 2>&1 || FAIL=1
    done
    if [ "$FAIL" = 0 ]; then
        rm -f "$BLACK_STATE"
    else
        return 1
    fi
}

# Finds out whether this Android can apply system colors, for the settings page.
# Android builds its color overlays through the overlay service; where that does
# not work (seen on an AppSupport 13) the overlay list is empty. The page reads
# the result from dconf and greys out the color options. Nothing is written
# while Android is not running, so an unknown state never hides anything.
detect_colors() {
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/100000/dbus/user_bus_socket"
    READY=$(appsupport-attach /system/bin/getprop sys.boot_completed 2>/dev/null | tr -d '\r\n ')
    [ "$READY" = "1" ] || return 0
    i=0
    while [ "$i" -lt 10 ]; do
        if appsupport-attach /system/bin/cmd overlay list 2>/dev/null | grep -Eq '^\[.\] '; then
            dconf write /desktop/ambience-sync/colors_supported true
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done
    dconf write /desktop/ambience-sync/colors_supported false
}

if [ "$1" = "--detect" ]; then
    detect_colors
    exit 0
fi

if [ "$1" = "--reset" ]; then
    reset_android
    reset_night
    reset_font
    reset_black
    exit 0
fi

# unset counts as off
ENABLED=$(read_conf /desktop/ambience-sync/enabled)
MONOCHROME=$(read_conf /desktop/ambience-sync/monochrome)
FOLLOW=$(read_conf /desktop/ambience-sync/follow_dark_mode)
FOLLOW_TEXT=$(read_conf /desktop/ambience-sync/follow_text_size)
PUREBLACK=$(read_conf /desktop/ambience-sync/pure_black)
PUREBLACK_ALL=$(read_conf /desktop/ambience-sync/pure_black_all)

# the extra level only counts while pure black itself is on
BLACK_RES="$BLACK_BASE"
if [ "$PUREBLACK" = "true" ] && [ "$PUREBLACK_ALL" = "true" ]; then
    BLACK_RES="$BLACK_BASE $BLACK_EXTRA"
fi
BLACK_COUNT=$(printf '%s\n' $BLACK_RES | wc -l | tr -d ' ')

# Sets (or resets) the Android system color from the highlight color
apply_color() {
    # this Android can't apply colors (see detect_colors): give back anything
    # we set earlier and leave it at that
    if [ "$(read_conf /desktop/ambience-sync/colors_supported)" = "false" ]; then
        reset_android
        return 0
    fi

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

    OLD=$(appsupport-attach /system/bin/settings get secure "$ANDROID_KEY" 2>/dev/null | tr -d '\r')
    [ "$OLD" = "$JSON" ] || COLOR_TOUCHED=1

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

# Matches Android's font size to Sailfish's text size (Settings > Display >
# Text size). The steps were matched by comparing the rendered text sizes.
apply_font() {
    SIZE=$(read_conf /desktop/jolla/theme/font/sizeCategory)
    case "$SIZE" in
        normal)   SCALE="1.0" ;;
        large)    SCALE="1.15" ;;
        huge)     SCALE="1.3" ;;
        gigantic) SCALE="1.5" ;;
        *)
            echo "Could not read text size from dconf" >&2
            return 1
            ;;
    esac

    # remember Android's current scale, once, before the first change
    if [ ! -e "$FONT_PREV" ]; then
        FPREV=$(appsupport-attach /system/bin/settings get system font_scale 2>/dev/null \
            | tr -d '\r\n ')
        # anything else means Android couldn't be reached: change nothing and
        # retry on the next run
        if [ "$FPREV" != "null" ] && ! printf '%s' "$FPREV" | grep -Eq '^[0-9](\.[0-9]{1,3})?$'; then
            return 1
        fi
        mkdir -p "$STATE_DIR"
        printf '%s\n' "$FPREV" > "$FONT_PREV"
    fi

    appsupport-attach /system/bin/settings put system font_scale "$SCALE" >/dev/null 2>&1
}

# True when all our overlays are enabled and none of SystemUI's own color overlays
# (com.android.systemui:neutral, accent, dynamic) is listed after them. The list
# is in priority order, so whatever comes last wins, and SystemUI's "dynamic"
# overlay defines the very same dark surface colors that we override.
black_in_order() {
    printf '%s\n' "$1" | awk -v pkg="$BLACK_PKG" -v want="$BLACK_COUNT" '
        /^[^[]/ && NF { g = $0 }
        index($0, "[x] com.android.systemui:") == 1 { sys[g] = NR }
        index($0, "[x] " pkg ":pb_") == 1 { n++; pg = g; if (!(g in first)) first[g] = NR }
        END { exit !(n == want && first[pg] > sys[pg]) }'
}

# True when the overlay list that is read right now is in order (see above).
black_verify() {
    V=$(appsupport-attach /system/bin/cmd overlay list 2>/dev/null) || return 1
    V=$(printf '%s\n' "$V" | tr -d '\r')
    black_in_order "$V"
}

# (Re)creates and enables all overlays. Each one is switched off first, so that it
# ends up last in the priority order, above SystemUI's. Overlays of ours that are
# enabled but no longer in $BLACK_RES (earlier versions, or the extra level that was
# switched off) are switched off.
#
# All steps are sent to Android in ONE call, so the overlays change within a few
# milliseconds and the screen flashes once, instead of once per overlay. $LIST is
# the overlay list that apply_black has just read.
black_force() {
    # marker first, so a half-finished run can still be undone
    mkdir -p "$STATE_DIR"
    : > "$BLACK_STATE"

    ACMD="/system/bin/cmd overlay"
    NAMES=$( {
        printf '%s\n' "$LIST" | grep -o "^\[x\] $BLACK_PKG:pb_[A-Za-z0-9_]*" | sed 's/^\[x\] //'
        for r in $BLACK_RES; do echo "$BLACK_PKG:pb_$r"; done
    } | sort -u )

    SCRIPT="f=0;"
    for o in $NAMES; do
        SCRIPT="$SCRIPT $ACMD disable --user 0 $o >/dev/null 2>&1;"
    done
    for r in $BLACK_RES; do
        SCRIPT="$SCRIPT $ACMD fabricate --target android --name pb_$r android:color/$r 0x1c 0xff000000 >/dev/null 2>&1 || f=1;"
    done
    for r in $BLACK_RES; do
        SCRIPT="$SCRIPT $ACMD enable --user 0 $BLACK_PKG:pb_$r >/dev/null 2>&1 || f=1;"
    done
    appsupport-attach /system/bin/sh -c "$SCRIPT exit \$f" >/dev/null 2>&1

    # appsupport-attach may not pass such a command on as it is, so check the
    # result, and if it is not right, do the same step by step instead
    black_verify && return 0

    for o in $NAMES; do
        appsupport-attach /system/bin/cmd overlay disable --user 0 "$o" >/dev/null 2>&1
    done
    FAIL=0
    for r in $BLACK_RES; do
        appsupport-attach /system/bin/cmd overlay fabricate --target android \
            --name "pb_$r" "android:color/$r" 0x1c 0xff000000 >/dev/null 2>&1 \
            && appsupport-attach /system/bin/cmd overlay enable --user 0 \
                "$BLACK_PKG:pb_$r" >/dev/null 2>&1 \
            || FAIL=1
    done
    [ "$FAIL" = 0 ]
}

# Makes Android's dark theme pure black: the colors in $BLACK_RES (the backgrounds,
# and with "Black cards and surfaces" the raised surfaces too) are overridden with
# #000000 through fabricated overlays. It only shows while Android is in
# its dark theme, so it does not depend on the ambience or the style setting.
#
# But whenever Android's color setting changes, SystemUI registers its own color
# overlays again a moment later, which puts them above ours and brings the gray
# back. So after such a change, keep checking for a few seconds ($SETTLE) and put
# ours back on top when needed. A normal run is one quick check that does nothing
# while everything is in order.
apply_black() {
    # this Android can't apply colors (see detect_colors): its overlay service
    # does not work, which pure black needs as well. Give back anything we set
    # earlier and leave it at that
    if [ "$(read_conf /desktop/ambience-sync/colors_supported)" = "false" ]; then
        reset_black
        return 0
    fi

    i=0
    while :; do
        LIST=$(appsupport-attach /system/bin/cmd overlay list 2>/dev/null) || return 1
        LIST=$(printf '%s\n' "$LIST" | tr -d '\r')
        # an empty list means Android could not be asked: change nothing and
        # retry on the next run
        printf '%s\n' "$LIST" | grep -Eq '^\[.\] ' || return 1

        black_in_order "$LIST" || black_force || return 1

        [ "$i" -ge "${SETTLE:-0}" ] && break
        i=$((i + 1))
        sleep 1
    done
    return 0
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

# the text size does not depend on the ambience
if [ "$1" != "--ambience-changed" ]; then
    if [ "$FOLLOW_TEXT" = "true" ]; then
        apply_font
    else
        reset_font
    fi
fi

# Pure black does not depend on the ambience, but a changed color setting makes
# Android register its color overlays again on top of ours, so it is checked after
# the color step, also on an ambience change.
if [ "$PUREBLACK" = "true" ]; then
    SETTLE=0
    if [ "$COLOR_TOUCHED" = 1 ]; then
        SETTLE=6
    fi
    apply_black
elif [ "$1" != "--ambience-changed" ]; then
    reset_black
fi
