#!/bin/sh
# Runs apply.sh now, then again whenever the ambience changes or one of the
# ambience-sync settings is changed. Runs as root.

APPLY="/usr/libexec/ambience-sync/apply.sh"

export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/100000/dbus/user_bus_socket"
export XDG_CONFIG_HOME="/home/defaultuser/.config"

# does this Android support colors? (in the background; it can take a while)
"$APPLY" --detect &

"$APPLY"

# settings page changes (switch or style); dconf watch prints the key path
dconf watch /desktop/ambience-sync/ |
while read -r line; do
    case "$line" in
        /desktop/ambience-sync/uninstall)
            # the settings page asks for removal by setting this key to true
            if [ "$(dconf read /desktop/ambience-sync/uninstall)" = "true" ]; then
                dconf reset /desktop/ambience-sync/uninstall
                # Run detached via systemd-run: removal stops this service,
                # which would kill a child started from here.
                if rpm -q ambience-sync >/dev/null 2>&1; then
                    systemd-run --no-block rpm -e ambience-sync
                else
                    # not installed from the RPM (install.sh): same steps as
                    # install.sh --uninstall
                    systemd-run --no-block /bin/sh -c '
                        systemctl disable ambience-sync-android.service
                        systemctl disable --now ambience-sync.service
                        /usr/libexec/ambience-sync/apply.sh --reset
                        rm -rf /usr/libexec/ambience-sync
                        rm -f /etc/systemd/system/ambience-sync.service
                        rm -f /etc/systemd/system/ambience-sync-android.service
                        rm -f /usr/share/jolla-settings/entries/ambience-sync.json
                        rm -rf /usr/share/jolla-settings/pages/ambience-sync
                        rm -f /usr/share/themes/sailfish-default/silica/z*/icons*/icon-m-ambience-sync.png
                        rm -rf /var/lib/ambience-sync
                        systemctl daemon-reload
                    '
                fi
            fi
            ;;
        /desktop/ambience-sync/*)
            "$APPLY"
            ;;
    esac
done &

# Sailfish text size changes (Settings > Display > Text size)
dconf watch /desktop/jolla/theme/font/ |
while read -r line; do
    case "$line" in
        /desktop/jolla/theme/font/sizeCategory)
            "$APPLY"
            ;;
    esac
done &

# ambience changes; the delay lets dconf finish writing the new colors
dbus-monitor --session "type='signal',interface='com.jolla.ambienced',member='contentChanged'" |
while read -r line; do
    case "$line" in
        *member=contentChanged*)
            sleep 1
            "$APPLY" --ambience-changed
            ;;
    esac
done
