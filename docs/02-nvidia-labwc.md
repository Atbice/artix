# 02 — RTX 3090 + labwc (Wayland) + greetd

labwc is a Wayland-native stackable compositor built on wlroots — think
"Openbox on Wayland". NVIDIA-Wayland on Ampere is well-behaved with the
590+/595 driver branch in 2026; labwc inherits the wlroots NVIDIA story
which closed most of its gaps through 2025. The NVIDIA config here is
unforgiving in one spot (KMS in initramfs) and lenient elsewhere.

## NVIDIA driver (this part is non-negotiable)

RTX 3090 = Ampere → the **current `nvidia-dkms` package** (NOT a legacy
470/535 branch). DKMS auto-rebuilds the module on kernel updates via
pacman hooks. `linux-lts-headers` is in `pkgs/pacman.txt` so the build
also targets the LTS fallback kernel. The driver auto-blacklists nouveau.

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
  initramfs (`MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)`).
  This is what gets you a clean KMS handover instead of a black screen
  during boot. `mkinitcpio -P` regenerates all presets — `bootstrap.sh`
  runs it.
- Verify after reboot: `cat /sys/module/nvidia_drm/parameters/modeset` → `Y`.
- No `GBM_BACKEND` / `__GLX_VENDOR_LIBRARY_NAME` env vars needed with
  the current driver. wlroots uses GBM by default for NVIDIA.

## labwc — minimum viable config

The `labwc` package installs the `labwc` binary. greetd (see below)
launches it directly. labwc handles `XDG_CURRENT_DESKTOP=labwc` and
`XDG_SESSION_TYPE=wayland` itself in recent versions.

You write **three files** under `~/.config/labwc/`:

### `~/.config/labwc/rc.xml` — behavior

```xml
<?xml version="1.0"?>
<labwc_config>
  <core>
    <decoration>server</decoration>
    <gap>4</gap>
    <adaptiveSync>fullscreen</adaptiveSync>
    <allowTearing>fullscreen</allowTearing>
  </core>

  <theme>
    <name>Default</name>
    <cornerRadius>6</cornerRadius>
    <font place="ActiveWindow">
      <name>JetBrains Mono</name>
      <size>10</size>
    </font>
  </theme>

  <keyboard>
    <default />
    <keybind key="W-Return"><action name="Execute" command="foot" /></keybind>
    <keybind key="W-d"><action name="Execute" command="fuzzel" /></keybind>
    <keybind key="W-S-q"><action name="Close" /></keybind>
    <keybind key="W-S-e"><action name="Exit" /></keybind>
    <keybind key="XF86AudioRaiseVolume"><action name="Execute" command="wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+" /></keybind>
    <keybind key="XF86AudioLowerVolume"><action name="Execute" command="wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-" /></keybind>
    <keybind key="XF86AudioMute"><action name="Execute" command="wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" /></keybind>
  </keyboard>

  <mouse>
    <default />
  </mouse>
</labwc_config>
```

`<adaptiveSync>fullscreen</adaptiveSync>` enables VRR on a per-window
basis when an app is fullscreen — exactly what you want for gaming.
`<allowTearing>fullscreen</allowTearing>` lets games request tearing
during fullscreen for lower input latency.

### `~/.config/labwc/autostart` — start Noctalia + portals + polkit

```sh
# Auto-start Noctalia v5 (built from source by bootstrap.sh)
noctalia &

# Polkit agent so password prompts work
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
```

`labwc` execs this script at session start. Anything you don't want
auto-started, omit.

### `~/.config/labwc/environment` — env vars exported into the session

```sh
XKB_DEFAULT_LAYOUT=no
XCURSOR_THEME=Adwaita
XCURSOR_SIZE=24
```

Outputs (monitor mode + scale + position) are set via `wlr-randr`
inside `autostart`, or via the more elaborate per-output blocks in
`rc.xml` (see the labwc-config(5) man page).

The full reference is at <https://labwc.github.io/labwc-config.5.html>.

## greetd + tuigreet

`bootstrap.sh` installs `/etc/greetd/config.toml`:

```toml
[terminal]
vt = 1
[default_session]
command = "tuigreet --remember --time --asterisks --cmd labwc"
user = "greeter"
```

The greeter runs on tty1 in text mode (no graphical greeter quirks
under NVIDIA), and `--cmd labwc` becomes the user's session after they
auth. For autologin, swap the `[default_session]` block for the
`[initial_session]` block (see the comments in the file).

## dinit services (Artix layout)

Service files live in `/etc/dinit.d/<name>` (or `/usr/lib/dinit.d/<name>`
when shipped by a package). Each is a declarative `key = value` file —
no run scripts. Enabling a service means symlinking it under
`/etc/dinit.d/boot.d/` so the `boot` target pulls it in; `dinitctl
enable` does that and brings the service up immediately. install.sh
already enables these via `dinitctl --offline enable` in the chroot:

- `dbus` — system bus (every session needs it)
- `elogind` — login + seat management
- `NetworkManager` — Ethernet/WiFi
- `zramen` — compressed swap

bootstrap.sh additionally enables `greetd` (the display manager).
Quick reference:

```sh
sudo dinitctl list                   # show all loaded services + status
sudo dinitctl status <name>          # one service
sudo dinitctl start <name>           # bring up now
sudo dinitctl stop <name>            # bring down now (stays enabled)
sudo dinitctl disable <name>         # remove from boot
```

## VRR + gaming on labwc

- **VRR**: `<adaptiveSync>fullscreen</adaptiveSync>` in rc.xml (shown
  above). Works on the proprietary NVIDIA driver on Wayland in 2026 via
  wlroots' adaptive-sync protocol.
- **HDR**: not supported by labwc. If you ever need desktop HDR, the
  answer is gamescope (per-game HDR override).
- **Tearing for low-latency gaming**: `<allowTearing>fullscreen</allowTearing>`
  in rc.xml lets games request the tearing-control protocol. Combine
  with `gamescope -e ... -- %command%` in Steam launch options for
  per-game control.
- **VRR + multi-monitor**: NVIDIA's old VRR signal-loss bug is fixed in
  580+. Should just work.

## Verifying after reboot

```sh
nvidia-smi                                           # 3090 visible
cat /sys/module/nvidia_drm/parameters/modeset        # -> Y
echo $XDG_SESSION_TYPE                                # -> wayland
echo $XDG_CURRENT_DESKTOP                             # -> labwc
wlr-randr                                             # lists your displays
vkcube                                                # 3090 renders
```

## Sources

- labwc upstream: <https://github.com/labwc/labwc>
- labwc-config(5): <https://labwc.github.io/labwc-config.5.html>
- Arch wiki — NVIDIA: <https://wiki.archlinux.org/title/NVIDIA>
- Arch wiki — labwc: <https://wiki.archlinux.org/title/Labwc>
- Artix wiki — dinit: <https://wiki.artixlinux.org/Main/Dinit>
- greetd: <https://man.sr.ht/~kennylevinsen/greetd/>
