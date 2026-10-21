#!/bin/sh
# CleanYourTV for LG webOS: uninstaller. Run on the TV as root:  sh /media/developer/cleanyourtv/uninstall.sh
# Restores LG's Home and services, removes the boot scripts and deletes /media/developer/cleanyourtv.
# Pass --keep-config to keep your settings (config.json) and usage history.
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
D=/media/developer/cleanyourtv
INITD=/var/lib/webosbrew/init.d
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
rm -f $INITD/10-cleanyourtv-home $INITD/15-cleanyourtv-debloat
[ -f $D/debloat-undo.sh ] && sh $D/debloat-undo.sh </dev/null
pkill -f "[1]0-cleanyourtv-home"   # the watchdog would restart the helper
pkill -f "[c]leanyourtv/helper.js"
if grep -q " /usr/palm/applications/com.webos.app.home " /proc/mounts; then sh $D/undo-home.sh temp </dev/null; fi
if [ "$1" = --keep-config ]; then mkdir -p /media/developer/cytv-keep; cp $D/config.json $D/usage.json /media/developer/cytv-keep/ 2>/dev/null; fi
luna-send -n 1 -w 20000 -f luna://com.webos.appInstallService/dev/remove '{"id":"com.cleanyourtv.live","subscribe":false}' </dev/null >/dev/null 2>&1
luna-send -n 1 -w 20000 -f luna://com.webos.appInstallService/dev/remove '{"id":"com.cleanyourtv.notify","subscribe":false}' </dev/null >/dev/null 2>&1
rm -rf /media/developer/apps/usr/palm/packages/com.cleanyourtv.notify /media/developer/apps/usr/palm/applications/com.cleanyourtv.notify
rm -rf /media/developer/apps/usr/palm/packages/com.cleanyourtv.live
rm -rf $D
[ "$1" = --keep-config ] && { mkdir -p $D; mv /media/developer/cytv-keep/* $D/ 2>/dev/null; rmdir /media/developer/cytv-keep; }
echo "[cleanyourtv] removed. LG's Home and services are back."
