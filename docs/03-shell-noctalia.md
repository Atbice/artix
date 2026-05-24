# 03 — Noctalia v5 desktop shell (source-built)

Noctalia v5 is a Wayland-native desktop shell — status bar, app
launcher, notifications, OSDs, lock screen, dock, and widgets, all in
one binary. v5 is a **ground-up rewrite** of v4: built directly on
Wayland + OpenGL ES, with **no Qt or GTK / no Quickshell dependency**.

> v5 is in **early development** per upstream — *"expect breaking
> configuration and behavior changes while the project is still taking
> shape."* That's the trade for getting the native-Wayland, no-QML
> shell early. If you want stability, the AUR `noctalia-shell` v4 line
> is the conservative path (we don't use it here).

## Why source-built, not AUR

Only v4 (`noctalia-shell` 4.7.7 at time of writing) is on AUR.
Upstream has been clear that v5 is the future and v4 issues will not
be merged. We bet on v5 from day one and build from the `v5` branch.
`bootstrap.sh` clones + builds + installs it idempotently — re-running
it does a `git fetch && reset --hard origin/v5` and rebuilds only if
the SHA changed.

## How it's built (handled by `bootstrap.sh`)

Section 7b of `bootstrap.sh`:

```sh
# Clone the v5 branch (or fetch + hard-reset if already there)
git clone -b v5 https://github.com/noctalia-dev/noctalia-shell.git ~/src/noctalia-shell

# Build with the upstream Justfile recipes (just is in pkgs/pacman.txt)
cd ~/src/noctalia-shell
just configure release      # meson setup with -Dbuildtype=release
just build release          # meson compile
sudo just install release   # meson install (default prefix /usr/local)
```

Installed paths (from the v5 README):

```
/usr/local/bin/noctalia
/usr/local/share/noctalia/assets/...
```

The Arch deps the v5 README lists (`meson gcc just wayland
wayland-protocols libglvnd freetype2 fontconfig cairo pango harfbuzz
libxkbcommon glib2 sdbus-cpp libpipewire polkit pam curl libwebp
librsvg`) are all in `pkgs/pacman.txt` — they install via pacman
before bootstrap.sh reaches the build step.

## How it starts

labwc execs `~/.config/labwc/autostart` at session start. That file
launches Noctalia:

```sh
# ~/.config/labwc/autostart
noctalia &
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
```

`noctalia` is on PATH (`/usr/local/bin`). To restart after a crash or
config change: `pkill noctalia && noctalia &` from a foot terminal, or
exit + re-login.

## Configuration

User config path is determined by Noctalia v5 itself (it's not QML
anymore, so the `~/.config/quickshell/noctalia/` path from v4 doesn't
apply). Check `noctalia --help` and `~/.config/noctalia/` after first
run.

If you want this config tracked in git, symlink the dir into your
dotfiles repo (this repo doesn't carry dotfiles — see
[docs/05-maintenance.md](./05-maintenance.md)).

## Fonts + icons

`pkgs/pacman.txt` installs noto + DejaVu + Liberation + JetBrains
Mono. v5 ships its own assets under `/usr/local/share/noctalia/assets/`
(installed by `just install release`). If icons render as boxes after
install, run `fc-cache -fv` and restart the shell.

## Portals (so screenshots, file pickers, screencast work)

`pkgs/pacman.txt` installs `xdg-desktop-portal`,
`xdg-desktop-portal-wlr` (the wlroots-native portal — handles
screencast/screen-share for labwc + every other wlroots compositor),
and `xdg-desktop-portal-gtk` (file pickers for GTK apps). The wlr
portal is what apps like OBS, Discord, and browsers talk to for
screen capture under labwc.

## Things Noctalia provides (don't double up)

Per upstream README — v5 (and v4) provide:

- status bar (workspaces, clock, tray, sound, network, battery)
- app launcher
- notifications + DND + history
- lock screen
- idle management + OSD (volume/brightness)
- wallpaper management (with Wallhaven integration)
- multi-monitor support
- dock + widgets

`pkgs/pacman.txt` still installs `fuzzel` and `mako` as **fallbacks** —
not autostarted, just there if you ever break Noctalia and need to log
in without a shell. Comment them out of `pacman.txt` if you want a
truly minimal box.

## Troubleshooting

- **Shell doesn't start**: from foot, run `noctalia` directly and read
  stderr. Common causes: a missing Wayland protocol (re-check
  `pkgs/pacman.txt`'s build deps), a `LIBGL` issue (NVIDIA driver not
  loaded — see [docs/02-nvidia-labwc.md](./02-nvidia-labwc.md)).
- **Build fails during bootstrap.sh**: re-run `just configure release`
  manually under `~/src/noctalia-shell` — meson will print the missing
  dep. Add it to `pkgs/pacman.txt`, re-run bootstrap.
- **Breaking change after `git pull`**: v5 is pre-alpha by upstream's
  own description. If a recent commit broke the shell, `git log
  --oneline origin/v5 -20` and pin to a known-good SHA temporarily by
  editing `~/src/noctalia-shell` to that ref, then re-running just
  build / install.
- **Tray icons missing**: confirm `xdg-desktop-portal-wlr` is running.
  No systemd — on dinit + elogind it's auto-spawned on D-Bus
  activation when an app first asks. `busctl --user list | grep
  portal` should show it after you open Firefox once.

## When v5 lands on AUR

Eventually `noctalia-shell` (or a `noctalia-v5` package) will track v5
on AUR. At that point: drop the source-build section from
`bootstrap.sh`, drop the build deps from `pkgs/pacman.txt`'s "Noctalia
v5 build deps" block, and put the AUR package name back in
`pkgs/aur.txt`. Until then, source build wins on currency.

## Sources

- Noctalia upstream (v5 branch): <https://github.com/noctalia-dev/noctalia-shell/tree/v5>
- v5 announcement: <https://noctalia.dev/blog/announcing-noctalia-v5>
- Noctalia docs: <https://docs.noctalia.dev>
- Noctalia Discord: <https://discord.noctalia.dev>
- labwc autostart format: <https://labwc.github.io/labwc-config.5.html>
