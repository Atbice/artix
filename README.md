# Artix Linux — lean gaming box (niri + Noctalia, native Steam + Faugus)

A **minimal, clean** Artix Linux (runit) install whose only job is: boot into
**niri** (scrollable-tiling Wayland), present a **Noctalia** desktop shell,
and run **Steam + Lutris + Faugus** with the **RTX 3090** driver correct.
Dual-booted on a separate disk; Bazzite stays untouched.

> Pivoted from **Void Linux + KDE Plasma** on 2026-05-22. Void was the right
> philosophy (lean, runit, in control) but the niri + Noctalia stack needs
> **Quickshell**, which is not in `void-packages` — that's the exact
> "unofficial single-maintainer repo or fragile source build" trap we
> already rejected for COSMIC. Artix (also runit) has access to the AUR,
> which packages all of niri, Quickshell, Noctalia, and Faugus with active
> maintainers. Same init philosophy, dramatically better packaging coverage
> for this stack.

## Locked decisions (this scope)

| Decision | Choice | Why |
|---|---|---|
| OS | **Artix Linux** | Runit available (same appeal as Void); AUR available (Void's missing piece). |
| Init | **runit** | Same model that drew us to Void. Boot is fast, supervision is dirt-simple, upstream is dead-stable (a feature on a daily-driver box). |
| Compositor | **niri** (Wayland, scrollable-tiling) | Modern Rust/smithay compositor with explicit NVIDIA support. VRR works on the proprietary driver in 2026. |
| Shell | **Noctalia** (via Quickshell) | QML-based desktop shell. Status bar + launcher + notifications + control center in one. AUR-packaged. |
| Display manager | **greetd + tuigreet** | TUI greeter on tty1 — no Qt/GTK at the greeter stage, no Wayland-NVIDIA greeter quirks, instant. |
| AUR helper | **paru** (`paru-bin`) | Bootstrapped from a one-time clone. Modern, fast, sensible defaults. |
| Driver | `nvidia-dkms` + `lib32-nvidia-utils` | RTX 3090 = Ampere → current branch. 32-bit libs mandatory or games won't launch. |
| Steam | **native `steam`** (multilib) | Arch handles Steam-Linux-Runtime cleanly; none of the Void gconv/libudev/nofile workarounds apply. |
| Faugus | **AUR** `faugus-launcher` | One paru command, fully packaged, bundles UMU + auto GE-Proton. |
| Also | native **`lutris`** | One pacman command, same job as Faugus (per-game Proton + GE-Proton). Use whichever UI you like. |
| Install | Separate disk, Bazzite untouched, two ESPs, firmware boot menu (`docs/01`) | Unchanged philosophy from the Void plan. |

### Honest notes

- **No HDR** under niri. We're explicit: you said you don't use it, so this
  isn't a loss. If you ever want HDR for a specific game, run it through
  gamescope (`pkgs/pacman.txt` has it commented; `docs/04-gaming.md`
  explains).
- **VRR** works — per-output `variable-refresh-rate` in
  `~/.config/niri/config.kdl` (see `docs/02-nvidia-niri.md`).
- **Quickshell + Noctalia from AUR** are the load-bearing pieces of this
  pivot. AUR packages are user-maintained — `paru` shows the PKGBUILD
  before each upgrade. Read them. The non-git variants (which we use)
  track tagged releases and are generally safe.

### Considered & deferred

- **Stay on Void Linux** (evaluated 2026-05-22): rejected — Quickshell is
  not in `void-packages`, source-builds on a rolling distro are fragile,
  unofficial single-maintainer xbps repos are the COSMIC-trap. Artix gives
  us the same init story (runit) plus AUR coverage of this stack.
- **COSMIC desktop** (evaluated 2026-05): still deferred. Was deferred under
  Void for the same packaging reason; under Artix, niri + Noctalia now
  scratch the "modern non-KDE Wayland" itch, so COSMIC is doubly unneeded.
  Revisit only when its NVIDIA + gaming story is solid (Epoch 2/3, ~2027).
- **OpenRC / dinit / s6** (other Artix init systems): runit picked. OpenRC
  is the biggest ecosystem but slowest boot; dinit is fast/modern but
  smaller community; s6 is the purist option with the steepest learning
  curve. runit matches what we already wanted.

## Repo layout

```
README.md                       this file
docs/
  01-install-artix.md           Artix runit install, dual-boot, two ESPs, Btrfs
  02-nvidia-niri.md             RTX 3090 + niri + greetd + runit services
  03-shell-noctalia.md          Quickshell + Noctalia from AUR, autostart, fonts/portals
  04-gaming.md                  native Steam + Lutris + Faugus (AUR), gamemode, mangohud
  05-maintenance.md             rolling-release survival (pacman + paru + snapper)
  06-cachyos-layer.md           OPTIONAL: x86-64-v3 rebuilds + linux-cachyos + ananicy
pkgs/
  pacman.txt                    official-repo packages (base+desktop+nvidia+gaming+fonts)
  aur.txt                       quickshell + noctalia-shell + faugus-launcher
  cachyos.txt                   OPTIONAL: linux-cachyos + ananicy-cpp-runit + cachyos rules
etc/
  modprobe.d/nvidia.conf        KMS + suspend memory preservation
  mkinitcpio.conf.d/nvidia.conf nvidia modules baked into initramfs
  greetd/config.toml            tuigreet → niri-session on tty1
services.txt                    runit services to symlink into /etc/runit/runsvdir/default
bootstrap.sh                    idempotent provisioner (multilib + pacman + paru + AUR + services)
```

## Use it

1. Install Artix on the second disk — `docs/01-install-artix.md` (disk 1
   physically disconnected, two ESPs, Btrfs root, GRUB to disk 2 only
   with `--removable`).
2. First boot to a TTY, then:
   ```sh
   sudo pacman -S git
   git clone <this repo> ~/void && cd ~/void
   ./bootstrap.sh   # multilib → pacman pkgs → nvidia config → mkinitcpio → runit services → paru → AUR
   sudo reboot
   ```
   Flags: `--no-aur` (skip paru + AUR — Noctalia not installed) ·
   `--no-update` · `--cachyos` (optional layer, see below) · `--dry-run`.
3. tuigreet on tty1 → log in → niri session.
4. Verify:
   ```sh
   nvidia-smi
   cat /sys/module/nvidia_drm/parameters/modeset    # -> Y
   echo $XDG_SESSION_TYPE                            # -> wayland
   echo $XDG_CURRENT_DESKTOP                         # -> niri
   ```
5. Noctalia auto-starts via the `spawn-at-startup "qs" "-c" "noctalia"`
   line in `~/.config/niri/config.kdl` (sample in `docs/02-nvidia-niri.md`).
6. Steam → log in → Settings → Compatibility → enable Steam Play for all
   titles. Faugus and Lutris are in Noctalia's app launcher.
7. VRR: per-output `variable-refresh-rate` in the niri config.

`bootstrap.sh` is idempotent, refuses to run on non-Artix, and never
touches disk 1 or the bootloader.

## Optional: CachyOS layer

A second pass on top of the base install: add the CachyOS repos
(x86-64-v3 optimized rebuilds), switch to `linux-cachyos`, and pull in
`ananicy-cpp` + CachyOS's per-app scheduling rules. **Run the base
bootstrap first and confirm everything works**, then re-run with
`--cachyos` to layer it on. Idempotent.

```sh
./bootstrap.sh --cachyos
```

Honest tradeoffs (Ryzen 5900X + RTX 3090, gaming + dev):

- **Real wins**: 5–15% on CPU-bound work (builds, compression), measurably
  snappier desktop under load (compile + game, stream + game).
- **Negligible** for pure GPU-bound gaming on a 3090 — the GPU is already
  the bottleneck.
- **Cost**: one extra "did anything pull systemd?" check per `pacman -Syu`.
  Artix's lack of a `systemd` package is the natural seatbelt: if a CachyOS
  rebuild ever demands systemd, pacman refuses the transaction.

Full howto, including the manual sysctl / udev / cpu-governor / zram /
scx-scheds porting recipes (the bits `cachyos-settings` would do on
CachyOS-the-distro but that pull systemd), lives in
[`docs/06-cachyos-layer.md`](./docs/06-cachyos-layer.md).

> **Note on the repo name**: the directory and remote are still called
> `void` for git-history continuity; the contents are Artix now. The path
> `/var/home/bice/dev/void` is intentional.
