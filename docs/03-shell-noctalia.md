# 03 — Noctalia (Quickshell) desktop shell

Noctalia is a Quickshell-based desktop shell — a status bar, app launcher,
notifications, OSDs, and a control center, all written in QML. It runs as
**`qs -c noctalia`** on top of niri. Both Quickshell and Noctalia are
installed from the AUR by `bootstrap.sh` via `paru`.

> The whole reason we left Void Linux: Quickshell is not in `void-packages`,
> and the unofficial-xbps-repo / source-build path is exactly the trap that
> killed COSMIC for this box. The AUR maintains both packages with multiple
> contributors and ties them to upstream releases. See `README.md`.

## Packages (installed by `bootstrap.sh`)

From `pkgs/aur.txt`:

```
quickshell
noctalia-shell
```

Both are AUR; `bootstrap.sh` clones `paru-bin` once, builds it as your user,
and then `paru -S --needed --noconfirm`s the AUR list as that same user.
**Don't** run paru as root (`makepkg` refuses it by design).

## How it starts

Noctalia is launched by niri at session start. The relevant line in
`~/.config/niri/config.kdl` is:

```kdl
spawn-at-startup "qs" "-c" "noctalia"
```

`qs` is the Quickshell binary; `-c noctalia` tells it to load the
`noctalia` configuration set (which is what `noctalia-shell` installs into
`/etc/xdg/quickshell/noctalia/` and/or `~/.config/quickshell/noctalia/`
depending on the upstream packaging — check after install with
`pacman -Ql noctalia-shell | grep quickshell` and adjust the `-c` arg if
the directory name differs).

If you ever need to restart the shell (after editing config, or after a
crash): `pkill qs` and let niri respawn it, or run `qs -c noctalia &` from
a foot terminal.

## Configuration

User-level Noctalia config lives under `~/.config/noctalia/` (or
`~/.config/quickshell/noctalia/` — varies with upstream version; check the
files Noctalia drops on first run). Most settings (theme, bar position,
modules, accent color, launcher behavior) have a control-center GUI in the
shell itself — start there before hand-editing QML.

If you want this config tracked in git, symlink the dir into this repo and
extend `bootstrap.sh` to install the symlink. Out of scope for the initial
provisioning.

## Fonts + icons

`pkgs/pacman.txt` installs noto + DejaVu + Liberation + JetBrains Mono.
Noctalia uses **Material Symbols** for its icons — they come bundled with
the `noctalia-shell` AUR package, so no extra font install is needed. If
icons render as boxes after install, log out/in once so fontconfig picks up
the new font dir.

## Portals (so screenshots, file pickers, screencast work)

`pkgs/pacman.txt` installs `xdg-desktop-portal`, `xdg-desktop-portal-gnome`,
and `xdg-desktop-portal-gtk`. niri itself doesn't ship a portal, so the
GNOME portal is what handles screencast (used by OBS, Discord, browsers).
The GTK portal handles file pickers for GTK apps.

No KDE portal: you removed Plasma. Nothing in this stack pulls Qt platform
plugins beyond what Quickshell needs.

## Things that come from Noctalia (don't double up)

Noctalia provides:

- status bar (workspaces, clock, tray, sound, network, battery)
- app launcher
- notification daemon
- screen lock UI (it calls swaylock under the hood, which we installed)
- on-screen volume/brightness display
- a basic control center

`pkgs/pacman.txt` still installs `fuzzel` and `mako` as **fallbacks** —
not autostarted, just there if you ever break Noctalia and need to log in
without a shell. Comment them out of `pacman.txt` if you want a truly
minimal box; everything will still work.

## Troubleshooting

- **Shell doesn't start**: from foot, `qs -c noctalia` and read the
  stderr — usually a QML import error pointing at a missing dep.
- **Tray icons missing**: confirm `xdg-desktop-portal` is running with
  `systemctl --user status xdg-desktop-portal` — wait, no systemd: on
  runit + elogind it's auto-spawned on D-Bus activation when an app first
  asks. `busctl --user list | grep portal` should show it after you open
  Firefox once.
- **Icons render as boxes**: log out/in to refresh fontconfig caches; if
  still broken, `fc-cache -fv` then restart the shell.
- **Crashes after a Quickshell update**: AUR ships `-git` variants you can
  pin to (`quickshell-git`, `noctalia-shell-git`) — but the non-git
  versions are usually safer. If you must downgrade, `paru` keeps cached
  builds in `~/.cache/paru/clone/<pkg>/`.

## Sources

- Quickshell: <https://quickshell.outfoxxed.me/>
- Quickshell on AUR: <https://aur.archlinux.org/packages/quickshell>
- Noctalia upstream: search "noctalia-shell" — the AUR package's `URL` field points at the current repo
- niri startup spawning: <https://github.com/YaLTeR/niri/wiki/Configuration:-Miscellaneous#spawn-at-startup>
