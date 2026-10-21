#!/bin/sh
# CleanYourTV for LG webOS: uninstaller. Run on the TV as root:  sh /media/developer/cleanyourtv/uninstall.sh
# Restores LG's Home and services, removes the boot scripts and deletes /media/developer/cleanyourtv.
# Pass --keep-config to keep config.json.
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
D=/media/developer/cleanyourtv
INITD=/var/lib/webosbrew/init.d
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
rm -f $INITD/10-cleanyourtv-home $INITD/15-cleanyourtv-debloat
[ -f $D/debloat-undo.sh ] && sh $D/debloat-undo.sh </dev/null
pkill -f "[1]0-cleanyourtv-home"   # the watchdog would restart the helper
pkill -f "[c]leanyourtv/helper.js"
if grep -q " /usr/palm/applications/com.webos.app.home " /proc/mounts; then sh $D/undo-home.sh temp </dev/null; fi
if [ "$1" = --keep-config ]; then cp $D/config.json /media/developer/cleanyourtv-config.json 2>/dev/null; fi
rm -rf $D
[ "$1" = --keep-config ] && { mkdir -p $D; mv /media/developer/cleanyourtv-config.json $D/config.json; }
echo "[cleanyourtv] removed. LG's Home and services are back."
