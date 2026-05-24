# Artix Linux — lean gaming box (labwc + Noctalia v5, native Steam + Faugus)

A **minimal, clean** Artix Linux (dinit) install whose only job is: boot into
**labwc** (Wayland stackable compositor, Openbox-style), present
**Noctalia v5** as the desktop shell, and run **Steam + Lutris + Faugus**
with the **RTX 3090** driver correct. Dual-booted on a separate disk;
Bazzite stays untouched.

> **Two scripts.** `install.sh` runs from the live ISO and produces a
> bootable Artix on disk 2. `bootstrap.sh` runs after first boot and
> turns that bare Artix into labwc + Noctalia v5 + Steam. Both are
> idempotent. Re-running them IS your recovery story (`docs/adr/0001`).

---

# Install walkthrough

The path from a blank disk to a working labwc desktop, in order. Skip
nothing — the disk-safety pattern is load-bearing.

## 0. Pre-flight checklist

- [ ] **Bazzite's disk physically unplugged** (NVMe: unscrew; SATA: pull
  the data cable). The installer can only wipe what it can see.
- [ ] BIOS confirms disk 1 is gone (`Setup → Storage`).
- [ ] Ethernet cable plugged into disk 2's box (Wi-Fi works too via
  `nmtui`, but Ethernet on a stationary gaming desktop is one less
  thing).
- [ ] USB stick, ≥4 GB, ready to flash.

## 1. Download + flash the live ISO

Get the **weekly** `artix-base-dinit-YYYYMMDD-x86_64.iso` from
<https://artixlinux.org/download.php> — the "Weekly ISO images" block,
**base** row. The stable ISO is known to fail for scripted installs
(see feribsd/artix-install's notes); the weekly is the supported path.

Flash to USB:

```sh
# Identify the USB device (NOT a real disk!)
lsblk -d -o NAME,SIZE,MODEL
sudo dd if=artix-base-dinit-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Or use Ventoy / Balena Etcher / Rufus / Popsicle — anything that does a
bit-exact USB flash.

## 2. Boot the live ISO

- Tap the firmware boot-menu key (F11/F12/Esc — board-specific) and
  pick the USB.
- Live ISO logs you in as `root` / `artix` on tty1.
- If your keymap isn't US: `loadkeys no-latin1` (or whichever).
- Network: plug Ethernet (DHCP picks up automatically) or `nmtui` for
  Wi-Fi. Confirm: `ping -c1 artixlinux.org`.

## 3. Run `install.sh`

```sh
pacman -Sy --noconfirm git
git clone https://github.com/Atbice/artix.git /root/artix
cd /root/artix

# Inspect what's about to happen — never run a destructive script blind:
./install.sh --help
lsblk -d -o NAME,SIZE,MODEL,SERIAL   # confirm the target disk

# Then go:
./install.sh --disk /dev/nvme1n1
```

What `install.sh` does, in order:

1. Guards: refuses if not Artix live ISO; warns if more than one disk
   visible.
2. Prints a plan summary (disk, partitions, init, kernels, microcode,
   networking, swap, bootloader, hostname/user/locale) and waits for
   you to type `INSTALL`.
3. Prompts for root + user passwords (via `stty -echo` — never on
   argv, never written to disk).
4. Partitions the target disk: 512 M EFI (FAT32) + remainder ext4.
   Single root, no `/home` split, no Btrfs subvolumes. See
   [`docs/adr/0001-ext4-no-snapshots.md`](./docs/adr/0001-ext4-no-snapshots.md)
   for the trade.
5. `basestrap`s: `base base-devel dinit dinit-rc elogind-dinit
   linux linux-lts linux-firmware amd-ucode networkmanager
   networkmanager-dinit zramen zramen-dinit grub efibootmgr git nano`.
6. Chroot config: timezone, locale, vconsole keymap, hostname,
   `/etc/hosts`, root + user passwords, sudoers `%wheel`, pacman
   ergonomics (`ParallelDownloads=5`, `Color`, `ILoveCandy`), enables
   `dbus elogind NetworkManager zramen` via `dinitctl --offline
   enable`, installs GRUB `--removable` on the target disk's ESP,
   `grub-mkconfig`.
7. Unmounts everything.

`./install.sh --help` prints the full flag list. `--dry-run` prints
every command without touching state. `--yes` skips the typed
confirmation (for fully automated rebuilds).

## 4. Reboot

`reboot` and remove the USB. Power off. Reconnect Bazzite's disk.
Power back on, tap the firmware boot menu, pick Artix. You land in a
TTY. Log in as your new user.

Quick sanity checks:

```sh
ip a                 # Ethernet got an address (NetworkManager up)
free -h              # zram shown as Swap
uname -r             # linux mainline; pick linux-lts from GRUB to verify it boots too
```

If either kernel fails to boot or nvidia-dkms wedges later, hold the
firmware boot key and pick **Bazzite** — that's your fallback while you
fix Artix (or re-run `install.sh + bootstrap.sh` to rebuild).

## 5. Run `bootstrap.sh`

```sh
sudo pacman -S git    # already there, but harmless
git clone https://github.com/Atbice/artix.git ~/artix && cd ~/artix
./bootstrap.sh        # multilib → pacman pkgs → nvidia config → mkinitcpio → dinit services → paru → AUR
sudo reboot
```

Flags: `--no-aur` (skip paru + AUR — Noctalia not installed) ·
`--no-update` · `--cachyos` (optional layer, see
[`docs/06-cachyos-layer.md`](./docs/06-cachyos-layer.md)) · `--dry-run`.

After reboot: tuigreet on tty1 → log in → labwc session, Noctalia v5
auto-starts via the `noctalia &` line in
`~/.config/labwc/autostart` (sample in
[`docs/02-nvidia-labwc.md`](./docs/02-nvidia-labwc.md)).

## 6. Verify desktop

```sh
nvidia-smi                                            # 3090 visible
cat /sys/module/nvidia_drm/parameters/modeset         # → Y
echo $XDG_SESSION_TYPE                                # → wayland
echo $XDG_CURRENT_DESKTOP                             # → labwc
```

Steam → log in → Settings → Compatibility → enable Steam Play for all
titles. Faugus and Lutris are in Noctalia's app launcher.

VRR + tearing: `<adaptiveSync>fullscreen</adaptiveSync>` and
`<allowTearing>fullscreen</allowTearing>` in
`~/.config/labwc/rc.xml`.

## 7. Optional: CachyOS perf layer

A second pass that adds the CachyOS repos (x86-64-v3 optimized
rebuilds), switches to `linux-cachyos`, and pulls in `ananicy-cpp` +
CachyOS's ananicy rules. **Run the base bootstrap first and confirm
everything works**, then:

```sh
./bootstrap.sh --cachyos
```

Honest tradeoffs and the parts that need manual porting (sysctl /
udev / cpu-governor / scx-scheds) live in
[`docs/06-cachyos-layer.md`](./docs/06-cachyos-layer.md).

---

# Appendix

## Locked decisions

| Decision | Choice | Why |
|---|---|---|
| OS | **Artix Linux** | Non-systemd with a choice of inits (same appeal as Void); AUR available (Void's missing piece). |
| Init | **dinit** | Same supervised-init philosophy as runit, but with a real dependency graph, declarative `key = value` service files, and an actively-developed upstream. Artix ships first-party `*-dinit` subpackages for every service we use. |
| Filesystem | **ext4**, single root | Best raw performance for gaming + dev. Rollback via Bazzite-fallback + idempotent install.sh, not snapshots. See [`docs/adr/0001-ext4-no-snapshots.md`](./docs/adr/0001-ext4-no-snapshots.md). |
| Kernels | **`linux` + `linux-lts`** | linux as daily driver; linux-lts as the "I can still boot" entry in GRUB when a kernel update breaks nvidia-dkms. |
| Microcode | **`amd-ucode`** | 5900X gets the latest AMD CPU patches loaded by GRUB at early boot. |
| Networking | **NetworkManager + networkmanager-dinit** | Matches Noctalia's network widget (talks to NM over D-Bus). `nmtui` handles WiFi from a TTY when needed. |
| Swap | **`zramen`** (compressed RAM swap) | ~8 GB zstd-compressed zram on 32 GB → ~16–20 GB effective. No disk wear. No hibernate. |
| Compositor | **labwc** (Wayland, stackable, Openbox-style) | wlroots-based, mature ecosystem, conventional floating + light tiling. Adaptive sync + tearing-control protocols supported. |
| Shell | **Noctalia v5** (source-built from `v5` branch) | Native Wayland/GLES rewrite — no Qt/GTK/Quickshell dependency. Pre-alpha upstream, breaking changes expected. v4 is the AUR-packaged conservative path; we bet on v5. See [`docs/03-shell-noctalia.md`](./docs/03-shell-noctalia.md). |
| Display manager | **greetd + tuigreet** | TUI greeter on tty1 — no Qt/GTK at the greeter stage, no Wayland-NVIDIA greeter quirks, instant. |
| AUR helper | **paru** (`paru-bin`) | Bootstrapped from a one-time clone. Modern, fast, sensible defaults. |
| Driver | `nvidia-dkms` + `lib32-nvidia-utils` | RTX 3090 = Ampere → current branch. 32-bit libs mandatory or games won't launch. |
| Steam | **native `steam`** (multilib) | Arch handles Steam-Linux-Runtime cleanly. |
| Faugus | **AUR** `faugus-launcher` | One paru command, fully packaged, bundles UMU + auto GE-Proton. |
| Also | native **`lutris`** | Per-game Proton + GE-Proton. Use whichever UI you like. |
| Install | Separate disk, Bazzite untouched, two ESPs, firmware boot menu | Disk-1 physically unplugged at install time. GRUB `--removable` to disk 2 only. |

### Honest notes

- **No HDR** under labwc. We're explicit: you don't use it, so this
  isn't a loss. If you ever want HDR for a specific game, run it
  through gamescope (`pkgs/pacman.txt` has it commented; `docs/04` explains).
- **VRR + tearing** work — `<adaptiveSync>fullscreen</adaptiveSync>`
  and `<allowTearing>fullscreen</allowTearing>` in
  `~/.config/labwc/rc.xml` (see `docs/02-nvidia-labwc.md`).
- **Noctalia v5 is the load-bearing risk**. It's pre-alpha upstream
  ("expect breaking configuration and behavior changes"). bootstrap.sh
  is built to re-fetch + rebuild idempotently, but if upstream pushes
  a bad commit you can pin to a known-good SHA — see
  `docs/05-maintenance.md`. The conservative fallback is `noctalia-shell`
  v4 from AUR, swappable in a few minutes.

## Considered & deferred

- **Btrfs + snapshot rollback** (evaluated 2026-05): rejected. ext4
  picked for raw performance; rollback story is "boot Bazzite or
  re-run install.sh" instead. Details in
  [`docs/adr/0001-ext4-no-snapshots.md`](./docs/adr/0001-ext4-no-snapshots.md).
- **Stay on Void Linux** (evaluated 2026-05-22): rejected — Quickshell
  is not in `void-packages`, source-builds on a rolling distro are
  fragile, unofficial single-maintainer xbps repos are the COSMIC-trap.
  (We've since dropped Quickshell entirely in favor of Noctalia v5's
  native-Wayland rewrite, but the Void packaging argument still applies
  to the v5 build-dep chain.)
- **niri** (evaluated 2026-05-22, flipped 2026-05-24): the original
  pick. Scrollable-tiling Rust/smithay compositor. Flipped to labwc
  for the more conventional floating+tiling workflow and the larger
  wlroots ecosystem. niri stays a perfectly valid alternative if
  scrollable-tiling clicks for you later.
- **Noctalia v4 (AUR)** (evaluated 2026-05-24): the conservative
  path. Stable QML/Quickshell shell at v4.7.7. We chose v5 instead
  for the native-Wayland future-proofing — but if v5 churn becomes
  painful, swapping back to v4 is editing `pkgs/aur.txt` to add
  `quickshell noctalia-shell` and reverting the source-build section
  in bootstrap.sh.
- **COSMIC desktop** (evaluated 2026-05): still deferred. labwc +
  Noctalia scratch the "modern non-KDE Wayland" itch. Revisit when its
  NVIDIA + gaming story is solid (Epoch 2/3, ~2027).
- **runit / OpenRC / s6** (other Artix init systems): dinit picked.
  runit is dead-stable but unordered; OpenRC is shell-script-heavy and
  slowest boot; s6 has the steepest learning curve. dinit wins on
  dependency ordering, declarative files, and active upstream.

## Repo layout

```
README.md                       this file
docs/
  01-install-artix.md           Artix dinit install, dual-boot, two ESPs, ext4
  02-nvidia-labwc.md            RTX 3090 + labwc + greetd + dinit services
  03-shell-noctalia.md          Noctalia v5 source build, autostart, fonts/portals
  04-gaming.md                  native Steam + Lutris + Faugus (AUR), gamemode, mangohud
  05-maintenance.md             rolling-release survival (pacman + paru + linux-lts fallback)
  06-cachyos-layer.md           OPTIONAL: x86-64-v3 rebuilds + linux-cachyos + ananicy
  adr/
    0001-ext4-no-snapshots.md   why ext4 over Btrfs (rollback strategy)
pkgs/
  pacman.txt                    official-repo packages (base+desktop+nvidia+gaming+fonts)
  aur.txt                       faugus-launcher (+ commented extras). Noctalia v5 not on AUR — source-built by bootstrap.sh.
  cachyos.txt                   OPTIONAL: linux-cachyos + ananicy-cpp + cachyos rules
etc/
  modprobe.d/nvidia.conf        KMS + suspend memory preservation
  mkinitcpio.conf.d/nvidia.conf nvidia modules baked into initramfs
  greetd/config.toml            tuigreet → labwc on tty1
services.txt                    dinit services to enable via `dinitctl enable`
install.sh                      live-ISO installer (partition + ext4 + basestrap + chroot config + GRUB)
bootstrap.sh                    post-install provisioner (multilib + pacman + paru + AUR + services)
```

> **Note on the repo name**: the directory used to be called `void`
> for git-history continuity from the Void pivot; the contents are
> Artix now. Paths like `/var/home/bice/dev/void` are intentional if
> you still see them.
