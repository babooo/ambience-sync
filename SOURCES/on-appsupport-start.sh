#!/bin/sh
# Started (as root) by ambience-sync-android.service whenever AppSupport
# starts. Waits until Android reports that it has finished booting, then
# re-applies the current ambience-sync settings, so a color change made while
# AppSupport was off isn't lost.

APPLY="/usr/libexec/ambience-sync/apply.sh"

# give up after about a minute
i=0
while [ "$i" -lt 60 ]; do
    ready=$(appsupport-attach /system/bin/getprop sys.boot_completed 2>/dev/null | tr -d '\r\n ')
    if [ "$ready" = "1" ]; then
        # small margin: Android's settings provider can lag behind boot_completed
        sleep 2
        exec "$APPLY"
    fi
    i=$((i + 1))
    sleep 1
done

echo "AppSupport did not report boot completed, nothing applied" >&2
exit 0
