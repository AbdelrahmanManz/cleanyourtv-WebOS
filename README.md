# CleanYourTV for LG webOS

An Apple TV-style home screen for **rooted LG webOS TVs**, plus a debloat of LG's ads and telemetry.
It replaces LG's Home app with a clean launcher: a dock of four favourite apps, a top shelf naming the
focused app with an ambient glow taken from its artwork, an app grid, an Inputs picker, a Settings
shortcut and a clock, all customisable from the remote. It reads your installed apps live, so new apps show up on their own.

Everything is **RAM-only**. Nothing under `/usr`, `/etc` or the firmware is modified, and a reboot
without the boot scripts brings LG's stock Home back.

> Inspired by [CleanYourTV](https://github.com/Gathin23/cleanyourtv) (Android TV, MIT licensed), whose home-screen design this follows.
> Developed and tested on an LG OLED65G26LA (G2), webOS 10.2.2 / webOS 25. Other models and firmware
> versions should work if they are rooted, but are untested; please report what you find.

## Requirements

- An LG webOS TV that is **already rooted** with the [Homebrew Channel](https://webosbrew.org)
  (see [rootmy.tv](https://rootmy.tv)), and SSH access as `root` (`ssh root@<tv-ip>`).
- The TV needs internet access (the installer downloads this repo) and the tools webOS already ships:
  `curl`, `tar`, `python3` and `node`.

## Install

Run this on your computer. It logs in to the TV and runs the installer there (replace `192.168.1.50`
with your TV's IP):

```sh
ssh root@192.168.1.50 'curl -fsSL https://raw.githubusercontent.com/lasharor/cleanyourtv-WebOS/main/install.sh | sh'
```

Already in an SSH session on the TV? Run just the `curl ... | sh` part.

Options go after `sh -s --`:

| Option | What it does |
|---|---|
| `--no-debloat` | Install the launcher only; leave LG's services and the hosts file alone. |
| `--no-start` | Install, but only take effect at the next reboot. |

```sh
ssh root@192.168.1.50 'curl -fsSL https://raw.githubusercontent.com/lasharor/cleanyourtv-WebOS/main/install.sh | sh -s -- --no-debloat'
```

The screen blinks once while the system app manager (`sam`) restarts, then the new Home appears. The
installer is safe to run again; it updates the launcher and keeps your `config.json`.

### What the installer does

1. Checks it is running as root on a rooted webOS TV, and saves the original state (stock Home
   `appinfo.json`, `/etc/hosts`, process and service lists) in `/media/developer/cleanyourtv/backup`.
2. Copies the launcher, a small root helper and the scripts to `/media/developer/cleanyourtv`.
3. Adds two boot scripts to the Homebrew Channel's `/var/lib/webosbrew/init.d/`:
   - `10-cleanyourtv-home` starts the helper and bind-mounts the launcher over
     `/usr/palm/applications/com.webos.app.home`, then restarts `sam` so it picks it up.
   - `15-cleanyourtv-debloat` (skipped with `--no-debloat`) runs the debloat a minute after boot.
4. Applies both immediately.

## Customise

Everything is changed in the launcher itself; there is nothing to edit by hand.

- **Hold OK on an app** (or press and hold with the pointer) for its menu: add it to the dock or replace a
  dock app, move it left or right within the dock, remove it from the dock, or hide it.
- **Hold OK on a top button** to remove it.
- **The Customise button** (top right) has: top buttons (remove, or add Inputs, Settings or any app),
  hidden apps (show them again) and a reset to the defaults.

Choices are saved on the TV in `/media/developer/cleanyourtv/config.json` and survive reboots and
reinstalls. You can still edit that file (or copy `config.example.json` there) if you prefer; it holds
`dock` (up to four app ids), `topbar` (buttons with `label`, `icon` and either `app` or `action`) and `hidden`.

## The debloat

Unless you pass `--no-debloat`, about a minute after every boot the script:

- stops `remotelogger`, `service-logger`, `contentminer` and `nudge`;
- stops `acr2`, `admanager`, `sportsalarm` and `adoverlay-service` from starting, by mounting a
  do-nothing stub over their binaries (they are started on demand, so stopping them is not enough);
- adds three LG ad servers (`eic.ads.lgtvcommon.com`, `nl.ad.lgsmartad.com`,
  `nl.info.lgsmartad.com`) to `/etc/hosts`, marked `# cleanyourtv-debloat`. Existing entries, such as
  update blocking from the Homebrew Channel, are untouched.

Nothing is uninstalled, and everything is undone by `debloat-undo.sh` or a reboot without the script.
If an app misbehaves, `touch /media/developer/cleanyourtv/DISABLE-DEBLOAT` and reboot.

## Getting back to LG's Home

| Situation | What to do |
|---|---|
| From the launcher | Select **Restore LG Home**, the last tile in the grid. Stock Home returns in about 15 s, until the next reboot. |
| Over SSH, until next reboot | `sh /media/developer/cleanyourtv/undo-home.sh temp` |
| Over SSH, permanently (boot scripts stay installed but do nothing) | `sh /media/developer/cleanyourtv/undo-home.sh`; remove the `DISABLE` file to switch back on. |
| Remove everything | `sh /media/developer/cleanyourtv/uninstall.sh` (add `--keep-config` to keep `config.json`). |
| TV shows a black screen and SSH still works | Run the second command above. |
| Boot crashed | The Homebrew Channel's failsafe mode skips all boot scripts; reboot again. |

If the helper stops responding for about a minute, a watchdog restores LG's Home on its own until the
next reboot.

## How it works

- LG's Home (`com.webos.app.home`) is a read-only system app, so the launcher is bind-mounted over its
  folder at boot. `stage-home.sh` builds the mounted folder from the launcher page plus an
  `appinfo.json` derived from **your TV's own** stock one (nothing of LG's is stored in this repo).
- `sam` reads app definitions only at startup, which is why it is restarted after the mount.
- The launcher is a plain web page. It talks to a small Node helper on `127.0.0.1:8765` that runs as
  root and wraps `luna-send` to list apps, serve their icons, launch them and read input status.
- Layout: `app/` (launcher page and icons), `helper/helper.js`, `scripts/` (boot, debloat and restore
  scripts), `install.sh`, `uninstall.sh`.

## Troubleshooting

- **Black screen after the installer or a reboot:** wait about a minute, then press Home. If it stays
  black, SSH in and run `sh /media/developer/cleanyourtv/undo-home.sh temp`.
- **An app is missing from the grid:** check it is not listed under `hidden`. Apps without a visible
  launch icon are not shown.
- **After a firmware update that removes root:** re-root the TV first, then run the installer again.

Use at your own risk. This modifies a running TV with root access; read `install.sh` and the scripts
in `scripts/` before running them.
