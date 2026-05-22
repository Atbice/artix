# 04 — Gaming: native Steam + Lutris + Faugus (Artix/Arch)

Scope: games running instantly. Steam from `[multilib]`, Lutris from
`[extra]`, Faugus from AUR. **No Steam-on-Void runtime hacks** are needed
here — Arch's Steam packaging handles SLR cleanly, and gconv/libudev/nofile
issues from the Void notes do not apply.

## Packages (already in `pkgs/pacman.txt` + `pkgs/aur.txt`)

From pacman:

```
steam               # multilib
lutris              # extra
gamemode  lib32-gamemode
mangohud  lib32-mangohud
wine  winetricks
lib32-nvidia-utils  # also in the nvidia doc; mandatory
libva-nvidia-driver # VA-API / NVDEC bridge
```

From AUR:

```
faugus-launcher
```

Proton ships with Steam — no separate DXVK/VKD3D install. Lutris pulls the
rest of its runners through pacman/AUR via its own GUI.

## Multilib (one-time)

`bootstrap.sh` uncomments `[multilib]` in `/etc/pacman.conf` before
installing. To check manually:

```sh
grep -A1 '^\[multilib\]' /etc/pacman.conf
# should show the include line uncommented
sudo pacman -Syy
```

If multilib isn't enabled, Steam won't even install (and 32-bit nvidia libs
won't, either — that's how games die).

## Steam — first run

1. Launch Steam from Noctalia's app launcher (or `steam` in foot), log in.
2. Settings → Compatibility → **Enable Steam Play for all other titles**
   (uses bundled Proton; no ProtonUp needed unless you want GE-Proton too).
3. Per game, Properties → Compatibility → pick a Proton version. Install.
4. Controllers: wired Xbox/PS5 work in-kernel; the `steam` package installs
   the Steam Input udev rules under `/usr/lib/udev/rules.d/`. If a pad
   enumerates but games see no input, you may need to log out/in once for
   the `input` group (added by `bootstrap.sh`) to apply.

## Lutris — for non-Steam / Epic / GOG

`lutris` is native pacman and handles everything Faugus does:

- Per-game Wine/Proton **prefixes**.
- Built-in **GE-Proton / Wine-GE downloader** (Lutris → Preferences → Runners).
- Native **UMU** integration.
- Epic/GOG via Lutris install scripts (search the lutris.net DB).

One pacman package, fully tracked, survives system upgrades.

## Faugus — when you want a per-game launcher

`faugus-launcher` from AUR is the clean way to use Faugus: it bundles UMU
and auto-downloads GE-Proton on first use. Run it from Noctalia's app
launcher.

Faugus and Lutris cover the same job (per-game Proton prefixes + GE-Proton);
use whichever UI you prefer — both are installed.

## Performance helpers (already installed, not auto-enabled)

- **gamemode**: launch a game with `gamemoderun <cmd>` — adjusts CPU governor,
  niceness, etc., for the duration of the game. In Steam, add
  `gamemoderun %command%` to per-game launch options.
- **mangohud**: overlay with FPS, CPU/GPU, frame timing. Steam launch
  option: `mangohud %command%`, or system-wide via
  `~/.config/MangoHud/MangoHud.conf`.

## Optional: gamescope (NOT installed by default)

`gamescope` (pacman, `[extra]`) is a micro-compositor you can run *per
game* for HDR override, integer scaling, frame limiting, or to avoid
Wayland-compositor quirks. Install with `sudo pacman -S gamescope` if
needed. Steam launch option example:
`gamescope -W 3840 -H 2160 -r 120 -- %command%`.

Not installed by default because:

- You said you don't use HDR (the main reason to bother with gamescope).
- It's another layer to debug if a game misbehaves.

## Things that DON'T apply here (vs. the old Void plan)

- ❌ `/usr/lib64/gconv` symlink — not needed; Arch ships gconv in the
  expected location.
- ❌ `GCONV_PATH` env var in `/etc/profile.d/` — not needed.
- ❌ `nofile` limits raise — Arch's PAM defaults are already 1048576 (or
  unlimited at root); only override if Proton actually complains.
- ❌ `LD_PRELOAD=/usr/lib/libudev.so.1` per-game launch options — not
  needed; Arch's steam-runtime cooperates with system libudev.
- ❌ Flatpak Steam considerations — we don't use Flatpak at all on this box.

## Sources

- Arch wiki — Steam: <https://wiki.archlinux.org/title/Steam>
- Arch wiki — Steam/Troubleshooting: <https://wiki.archlinux.org/title/Steam/Troubleshooting>
- Lutris: <https://lutris.net/>
- Faugus AUR page: <https://aur.archlinux.org/packages/faugus-launcher>
- Gamemode: <https://github.com/FeralInteractive/gamemode>
