# 02 — RTX 3090 + niri (Wayland) + greetd

niri is a Wayland-native scrollable-tiling compositor (smithay-based, Rust).
NVIDIA-Wayland on Ampere is well-behaved in 2026 with the 590+/595 driver
branch — but niri pushes a few more edge cases than KDE Plasma, so the
NVIDIA config here is unforgiving in one spot (KMS in initramfs) and lenient
elsewhere.

## NVIDIA driver (this part is non-negotiable)

RTX 3090 = Ampere → the **current `nvidia-dkms` package** (NOT a legacy
470/535 branch). DKMS auto-rebuilds the module on kernel updates via
pacman hooks. The driver auto-blacklists nouveau.

- **`lib32-nvidia-utils`** from `[multilib]` — *mandatory*; without it
  Steam/Proton games will not launch. `bootstrap.sh` enables multilib in
  `/etc/pacman.conf` before installing pkgs/pacman.txt.
- `etc/modprobe.d/nvidia.conf` (installed by `bootstrap.sh`):
  ```
  options nvidia-drm modeset=1 fbdev=1
  options nvidia NVreg_PreserveVideoMemoryAllocations=1
  options nvidia NVreg_TemporaryFilePath=/var/tmp
  ```
- `etc/mkinitcpio.conf.d/nvidia.conf` bakes the nvidia modules into the
  initramfs (`MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)`). This
  is what gets you a clean KMS handover instead of a black screen during
  boot. `mkinitcpio -P` regenerates all presets — `bootstrap.sh` runs it.
- Verify after reboot: `cat /sys/module/nvidia_drm/parameters/modeset` → `Y`.
- No `GBM_BACKEND` / `__GLX_VENDOR_LIBRARY_NAME` env vars needed with the
  current driver. GBM is the default for niri.

## niri — minimum viable config

The `niri` package installs `niri` + `niri-session`. greetd (see below)
launches `niri-session`, which exports the standard
`XDG_CURRENT_DESKTOP=niri` and `XDG_SESSION_TYPE=wayland` to the user
session bus. You only need to write `~/.config/niri/config.kdl`.

A skeleton that handles NVIDIA, VRR, and spawning Noctalia at startup:

```kdl
// ~/.config/niri/config.kdl

input {
    keyboard {
        xkb {
            layout "no"        // change to your keymap
        }
    }
    touchpad { tap; natural-scroll; }
    mouse { accel-speed 0.0; }
}

output "DP-1" {
    // Change to the EDID/name of your actual display (`niri msg outputs`
    // after first boot lists them).
    mode "3840x2160@120.000"
    scale 1.5
    // Adaptive Sync (VRR). NVIDIA G-Sync Compatible monitors work here.
    variable-refresh-rate
}

// Auto-start at session login. The shell + a notification daemon.
spawn-at-startup "qs" "-c" "noctalia"

// (Optional) Auto-start a polkit agent so password prompts work.
spawn-at-startup "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"

// Key bindings — niri ships sensible defaults; only override what you want.
binds {
    Mod+Return       { spawn "foot"; }
    Mod+D            { spawn "fuzzel"; }      // Noctalia has its own launcher; this is a backup
    Mod+Shift+Q      { close-window; }
    Mod+Shift+E      { quit; }                // log out
    XF86AudioRaiseVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
    XF86AudioLowerVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
    XF86AudioMute        { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
}
```

The full reference is at <https://github.com/YaLTeR/niri/wiki>.

## greetd + tuigreet

`bootstrap.sh` installs `/etc/greetd/config.toml`:

```toml
[terminal]
vt = 1
[default_session]
command = "tuigreet --remember --time --asterisks --cmd niri-session"
user = "greeter"
```

The greeter runs on tty1 in text mode (no graphical greeter quirks under
NVIDIA), and `--cmd niri-session` is what becomes the user's session after
they auth. For autologin, swap the `[default_session]` block for the
`[initial_session]` block (see the comments in the file).

## dinit services (Artix layout)

Service files live in `/etc/dinit.d/<name>` (or `/usr/lib/dinit.d/<name>`
when shipped by a package). Each is a declarative `key = value` file —
no run scripts. Enabling a service means symlinking it under
`/etc/dinit.d/boot.d/` so the `boot` target pulls it in; `dinitctl
enable` does that and brings the service up immediately.

`bootstrap.sh` enables these:

```sh
sudo dinitctl enable dbus
sudo dinitctl enable NetworkManager
sudo dinitctl enable elogind         # if pkg ships a service file
sudo dinitctl enable greetd
```

Order doesn't matter at enable-time — dinit reads `depends-on =` /
`waits-for =` lines in the service files themselves and starts services
in the right order (greetd waits for dbus + elogind, NetworkManager
waits for dbus, etc). The Artix `*-dinit` subpackages declare these
deps already.

Quick reference:

```sh
sudo dinitctl list                   # show all loaded services + status
sudo dinitctl status <name>          # one service
sudo dinitctl start <name>           # bring up now
sudo dinitctl stop <name>            # bring down now (stays enabled)
sudo dinitctl disable <name>         # remove from boot
```

## VRR + gaming on niri

- **VRR**: per-output `variable-refresh-rate` in the niri config (shown
  above). Works on the proprietary NVIDIA driver on Wayland in 2026.
- **HDR**: not supported by niri. If you ever need desktop HDR, the answer
  is gamescope (per-game HDR override) or a second session (e.g. SDDM+KDE),
  which we deliberately did not install. You said you don't use HDR, so
  this is fine.
- **Tearing for low-latency gaming**: niri supports `allow-when-fullscreen`
  on a per-window-rule basis — see the wiki.
- **VRR + multi-monitor**: NVIDIA's old VRR signal-loss bug is fixed in
  580+. Should just work.

## Verifying after reboot

```sh
nvidia-smi                                           # 3090 visible
cat /sys/module/nvidia_drm/parameters/modeset        # -> Y
echo $XDG_SESSION_TYPE                                # -> wayland
echo $XDG_CURRENT_DESKTOP                             # -> niri
niri msg outputs                                      # lists your displays
vkcube                                                # 3090 renders
```

## Sources

- niri wiki: <https://github.com/YaLTeR/niri/wiki>
- Arch wiki — NVIDIA: <https://wiki.archlinux.org/title/NVIDIA>
- Arch wiki — niri: <https://wiki.archlinux.org/title/Niri>
- Artix wiki — dinit: <https://wiki.artixlinux.org/Main/Dinit>
- dinit upstream + docs: <https://github.com/davmac314/dinit>
- greetd: <https://man.sr.ht/~kennylevinsen/greetd/>
