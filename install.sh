#!/bin/sh
# CleanYourTV for LG webOS: installer. Run ON the TV, as root (see README.md).
#
#   curl -fsSL https://raw.githubusercontent.com/lasharor/cleanyourtv-WebOS/main/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --no-debloat     # launcher only, leave LG's services alone
#   curl -fsSL .../install.sh | sh -s -- --no-start       # install, but only take effect on the next reboot
#
# Environment: CYTV_REPO=owner/name  CYTV_REF=branch  CYTV_SRC=/path/to/repo-checkout (use a local copy instead of downloading)

main() {
  REPO="${CYTV_REPO:-lasharor/cleanyourtv-WebOS}"
  REF="${CYTV_REF:-main}"
  D=/media/developer/cleanyourtv
  INITD=/var/lib/webosbrew/init.d
  DEBLOAT=1; START=1
  for a in "$@"; do
    case "$a" in
      --no-debloat) DEBLOAT=0 ;;
      --no-start) START=0 ;;
      -h|--help) sed -n '2,9p' "$0" 2>/dev/null; return 0 ;;
      *) echo "unknown option: $a"; return 1 ;;
    esac
  done
  export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH

  say() { echo "[cleanyourtv] $*"; }
  die() { echo "[cleanyourtv] ERROR: $*" >&2; exit 1; }

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
  rm -f $D/DISABLE $D/DISABLE-DEBLOAT

  ln -sf $D/10-cleanyourtv-home $INITD/10-cleanyourtv-home
  if [ $DEBLOAT = 1 ]; then
    ln -sf $D/15-cleanyourtv-debloat $INITD/15-cleanyourtv-debloat
  else
    rm -f $INITD/15-cleanyourtv-debloat
  fi
  say "boot scripts installed in $INITD"

  # ---- go live ----
  if [ $START = 1 ]; then
    say "starting (the screen blinks once while the system app manager restarts)"
    sh $D/10-cleanyourtv-home </dev/null
    [ $DEBLOAT = 1 ] && sh $D/debloat-stop.sh </dev/null
    say "done. Edit $D/config.json to choose your dock and top buttons."
  else
    say "done. Everything takes effect at the next reboot."
  fi
  say "Back to LG's Home any time: pick 'Restore LG Home' at the end of the app grid,"
  say "or run: sh $D/undo-home.sh      Remove everything: sh $D/uninstall.sh"
}
main "$@"
