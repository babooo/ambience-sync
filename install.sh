#!/bin/sh
# Installs (or with --uninstall removes) ambience-sync without building an RPM.
# Run as root from inside the unpacked folder.

set -e
cd "$(dirname "$0")"

if [ "$(id -u)" != "0" ]; then
    echo "Run this as root (devel-su)" >&2
    exit 1
fi

if [ "$1" = "--uninstall" ]; then
    systemctl disable ambience-sync-android.service || :
    systemctl disable --now ambience-sync.service || :
    /usr/libexec/ambience-sync/apply.sh --reset || :
    rm -rf /usr/libexec/ambience-sync
    rm -f /etc/systemd/system/ambience-sync.service
    rm -f /etc/systemd/system/ambience-sync-android.service
    rm -f /usr/share/jolla-settings/entries/ambience-sync.json
    rm -rf /usr/share/jolla-settings/pages/ambience-sync
    rm -f /usr/share/themes/sailfish-default/silica/z*/icons*/icon-m-ambience-sync.png
    rm -rf /var/lib/ambience-sync
    systemctl daemon-reload
    exit 0
fi

#Check if Appsupport is installed and version if it is(=>13).
VER=$(rpm -qa | sed -n 's/^appsupport\([0-9][0-9]*\)-system-.*/\1/p' | sort -n | tail -n1)
if [ -z "$VER" ]; then
    echo "ambience-sync needs Android AppSupport, which is not installed." >&2
    exit 1
fi
if [ "$VER" -lt 13 ]; then
    echo "ambience-sync needs Android 13 or newer (found Android $VER)." >&2
    exit 1
fi

install -d /usr/libexec/ambience-sync
install -m 0755 apply.sh /usr/libexec/ambience-sync/apply.sh
install -m 0755 watch.sh /usr/libexec/ambience-sync/watch.sh
install -m 0755 on-appsupport-start.sh /usr/libexec/ambience-sync/on-appsupport-start.sh
install -m 0644 ambience-sync.service /etc/systemd/system/ambience-sync.service
install -m 0644 ambience-sync-android.service /etc/systemd/system/ambience-sync-android.service
install -d /usr/share/jolla-settings/entries
install -m 0644 ambience-sync.json /usr/share/jolla-settings/entries/ambience-sync.json
install -d /usr/share/jolla-settings/pages/ambience-sync
install -m 0644 ambience-sync.qml /usr/share/jolla-settings/pages/ambience-sync/ambience-sync.qml

# theme icons: one size per scale folder, in both the normal and monochrome sets
THEME="/usr/share/themes/sailfish-default/silica"
for scale in z1.0 z1.25 z1.5 z1.5-large z1.75 z2.0 z2.5; do
    [ -d "$THEME/$scale" ] || continue
    for sub in icons icons-monochrome; do
        install -d "$THEME/$scale/$sub"
        install -m 0644 "icons/$scale/icon-m-ambience-sync.png" "$THEME/$scale/$sub/icon-m-ambience-sync.png"
    done
done

systemctl daemon-reload
systemctl enable ambience-sync.service
systemctl enable ambience-sync-android.service
systemctl restart ambience-sync.service
