#!/bin/sh
# CleanYourTV for LG webOS: installer. Run ON the TV, as root (see README.md).
#
#   curl -fsSL https://raw.githubusercontent.com/lasharor/cleanyourtv-WebOS/main/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --no-debloat     # launcher only, leave LG's services alone
#   curl -fsSL .../install.sh | sh -s -- --no-start       # install, but only take effect on the next reboot
#   curl -fsSL .../install.sh | sh -s -- --no-verify      # skip the post-install check and automatic rollback
#   curl -fsSL .../install.sh | sh -s -- --force          # continue even if this TV looks unsupported
#
# Environment: CYTV_REPO=owner/name  CYTV_REF=branch  CYTV_SRC=/path/to/repo-checkout (use a local copy instead of downloading)

main() {
  REPO="${CYTV_REPO:-lasharor/cleanyourtv-WebOS}"
  REF="${CYTV_REF:-main}"
  D=/media/developer/cleanyourtv
  INITD=/var/lib/webosbrew/init.d
  TESTED_SDK="10."          # firmware this has been tried on: webOS 25 (sdkVersion 10.x)
  DEBLOAT=1; START=1; VERIFY=1; FORCE=0
  for a in "$@"; do
    case "$a" in
      --no-debloat) DEBLOAT=0 ;;
      --no-start) START=0 ;;
      --no-verify) VERIFY=0 ;;
      --force) FORCE=1 ;;
      -h|--help) sed -n '2,10p' "$0" 2>/dev/null; return 0 ;;
      *) echo "unknown option: $a"; return 1 ;;
    esac
  done
  export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH

  say() { echo "[cleanyourtv] $*"; }
  warn() { echo "[cleanyourtv] WARNING: $*" >&2; }
  die() { echo "[cleanyourtv] ERROR: $*" >&2; exit 1; }
  luna() { luna-send -n 1 -w 5000 -f "luna://$1" "$2" </dev/null 2>/dev/null; }

  # ---- preflight ----
  [ "$(id -u)" = 0 ] || die "run as root (ssh root@<tv-ip>)"
  command -v luna-send >/dev/null || die "this does not look like webOS (no luna-send)"
  [ -d "$INITD" ] || die "$INITD not found: root with the Homebrew Channel is required (https://rootmy.tv)"
  [ -w /media/developer ] || die "/media/developer is not writable"
  for t in curl tar python3 node; do command -v $t >/dev/null || die "missing tool: $t"; done
  HOME_DIR=/usr/palm/applications/com.webos.app.home
  [ -f $HOME_DIR/appinfo.json ] || die "stock Home app not found at $HOME_DIR"
  if grep -q " $HOME_DIR " /proc/mounts && [ ! -f $D/backup/home-appinfo.orig.json ]; then
    die "Home is already replaced but no backup exists; reboot the TV once, then run this again"
  fi

  # ---- is this a TV we know? (a warning, not a block, unless the Home app looks different) ----
  info=$(luna com.webos.service.tv.systemproperty/getSystemInfo '{"keys":["modelName","firmwareVersion","sdkVersion"]}')
  model=$(echo "$info" | sed -n 's/.*"modelName": *"\([^"]*\)".*/\1/p')
  fw=$(echo "$info" | sed -n 's/.*"firmwareVersion": *"\([^"]*\)".*/\1/p')
  sdk=$(echo "$info" | sed -n 's/.*"sdkVersion": *"\([^"]*\)".*/\1/p')
  say "TV: ${model:-unknown model}, firmware ${fw:-?}, webOS SDK ${sdk:-?}"
  case "$sdk" in
    $TESTED_SDK*) ;;
    *) warn "only webOS SDK $TESTED_SDK* (webOS 25) has been tested; other versions may behave differently. The original state is backed up and 'undo-home.sh' restores LG's Home." ;;
  esac
  SRCINFO=$D/backup/home-appinfo.orig.json
  [ -f "$SRCINFO" ] || SRCINFO=$HOME_DIR/appinfo.json
  python3 - "$SRCINFO" <<'PY' || { [ $FORCE = 1 ] && warn "continuing because of --force" || die "LG's Home app looks different from what this installer expects (use --force to try anyway)"; }
import json, sys
o = json.load(open(sys.argv[1]))
sys.exit(0 if o.get('id') == 'com.webos.app.home' and o.get('type') in ('flutter', 'web') else 1)
PY

  # ---- fetch ----
  if [ -n "$CYTV_SRC" ]; then
    SRC="$CYTV_SRC"
  else
    T=$(mktemp -d /tmp/cytv.XXXXXX) || die "mktemp failed"
    say "downloading $REPO ($REF)"
    curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF" | tar xz -C "$T" || die "download failed"
    SRC=$(ls -d "$T"/*/ 2>/dev/null | head -1)
  fi
  [ -f "$SRC/app/index.html" ] || die "launcher files not found in the download"
  trap '[ -n "$T" ] && rm -rf "$T"' EXIT
  VERSION=$(sed -n "s/^const VERSION = '\(.*\)';/\1/p" "$SRC/helper/helper.js" | head -1)

  # ---- back up the original state (first run only) ----
  mkdir -p $D/backup
  [ -f $D/backup/home-appinfo.orig.json ] || cp $HOME_DIR/appinfo.json $D/backup/home-appinfo.orig.json
  [ -f $D/backup/hosts.orig ] || cp /etc/hosts $D/backup/hosts.orig
  [ -f $D/backup/processes.orig.txt ] || { ps > $D/backup/processes.orig.txt 2>&1; systemctl list-units --no-legend > $D/backup/units.orig.txt 2>&1; date > $D/backup/date.txt; }
  say "original state saved in $D/backup"

  # ---- install files ----
  mkdir -p $D/app
  cp "$SRC"/app/* $D/app/
  cp "$SRC"/helper/helper.js $D/
  cp "$SRC"/scripts/* "$SRC"/uninstall.sh $D/
  chmod +x $D/*.sh $D/10-cleanyourtv-home $D/15-cleanyourtv-debloat
  [ -f $D/config.json ] || cp "$SRC/config.example.json" $D/config.json
  echo "$REPO $REF" > $D/source
  rm -f $D/DISABLE $D/DISABLE-DEBLOAT

  ln -sf $D/10-cleanyourtv-home $INITD/10-cleanyourtv-home
  if [ $DEBLOAT = 1 ]; then
    ln -sf $D/15-cleanyourtv-debloat $INITD/15-cleanyourtv-debloat
  else
    rm -f $INITD/15-cleanyourtv-debloat
  fi
  say "version ${VERSION:-?}; boot scripts installed in $INITD"

  # ---- go live ----
  if [ $START = 0 ]; then
    say "done. Everything takes effect at the next reboot."
    return 0
  fi
  say "starting (the screen blinks once while the system app manager restarts)"
  pkill -f "[c]leanyourtv/helper.js"; sleep 1   # an older helper must not keep serving
  sh $D/10-cleanyourtv-home </dev/null
  [ $DEBLOAT = 1 ] && sh $D/debloat-stop.sh </dev/null

  # ---- verify, and roll back if the new Home did not come up ----
  if [ $VERIFY = 1 ]; then
    say "checking that the new Home came up..."
    ok=0
    for i in $(seq 1 40); do
      sleep 3
      type=$(luna com.webos.applicationManager/getAppInfo '{"id":"com.webos.app.home"}' | sed -n 's/.*"type": *"\([^"]*\)".*/\1/p' | head -1)
      hv=$(curl -s -m 3 http://127.0.0.1:8765/api/version | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
      if [ "$type" = web ] && [ "$hv" = "$VERSION" ]; then ok=1; break; fi
    done
    if [ $ok = 0 ]; then
      warn "the new Home did not come up (app type: ${type:-none}, helper: ${hv:-not answering}); rolling back"
      sh $D/undo-home.sh temp </dev/null
      rm -f $INITD/10-cleanyourtv-home $INITD/15-cleanyourtv-debloat
      die "rolled back: LG's Home is restored and the boot scripts are removed. Nothing else was changed. Details: /tmp/cleanyourtv-helper.log"
    fi
  fi
  say "done. Hold OK on an app to customise the dock, or use the Customise button at the top right."
  say "Back to LG's Home any time: pick 'Restore LG Home' at the end of the app grid,"
  say "or run: sh $D/undo-home.sh      Update: sh $D/update.sh      Remove everything: sh $D/uninstall.sh"
}
main "$@"
