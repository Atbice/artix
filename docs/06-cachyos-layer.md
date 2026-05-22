# 06 — Optional CachyOS layer (x86-64-v3 rebuilds + kernel + tuning)

A second pass on top of the base Artix install: add the CachyOS repos so
optimized rebuilds replace Arch packages in-place, switch to the
`linux-cachyos` kernel, and pull in `ananicy-cpp` + CachyOS's ananicy rules
for per-app scheduling tweaks.

> Run the base bootstrap (`./bootstrap.sh`) WITHOUT `--cachyos` first.
> Verify the box boots, NVIDIA works, Steam launches a game. Only then
> re-run with `--cachyos`. This gives you a known-good rollback target.

## What this layer is — and isn't

**Is:**
- x86-64-v3 optimized rebuilds of normal Arch packages (Zen 3, your 5900X,
  is v3-capable; not v4 — that needs AVX-512 which arrived with Zen 4).
- `linux-cachyos` kernel (BORE + sched-ext patches by default).
- `ananicy-cpp` (runit variant from Artix) + CachyOS's ananicy rules.

**Isn't:**
- CachyOS-the-distro. We're cherry-picking the repos; init stays runit.
- `cachyos-settings` (the all-in-one tuning meta). It ships systemd units
  + scripts that assume systemd. We port the bits we want manually.
- `power-profiles-daemon` / `thermald` (systemd-only on a desktop you
  don't need them).
- `cachyos-zram-config` (uses `zram-generator`, systemd-only). Use Artix's
  `zram-runit` if you want zram.

## Is it worth the maintenance cost?

Honest table for this box (5900X + RTX 3090, daily-driver gaming + dev):

| Area | x86-64-v3 rebuilds | linux-cachyos | ananicy-cpp |
|---|---|---|---|
| Game FPS | negligible (3090-bound) | small in CPU-bound games | small |
| Build times / compression | **5-15% faster** | small | small |
| Desktop responsiveness under load (compile + game, stream + game) | small | **noticeable** | noticeable |
| Boot time | small | small | none |

Costs:
- One extra check per `pacman -Syu`: did any rebuild add a `systemd` dep?
  If yes (rare) you skip that package and pin to the Artix/Arch version.
- The CachyOS kernel is one more thing to update + verify with DKMS.
  `linux-lts` as a fallback boot entry is highly recommended.
- Rolling-on-rolling means doubled breakage surface. Snapshot before
  every `-Syu`.

If you compile a lot of Rust or stream + game simultaneously, this layer
pays off. If you mostly play one game at a time, the GPU is the
bottleneck and the perf delta is hard to measure.

## Prereqs

- Base `./bootstrap.sh` has run successfully and you've rebooted into a
  working niri session at least once.
- A fresh Btrfs snapshot:
  ```sh
  sudo btrfs subvolume snapshot -r / /.snapshots/$(date +%F-%H%M)-pre-cachyos
  ```
- ~3–4 GB free disk: the v3 rebuilds redownload almost the entire
  installed package set.

## What `./bootstrap.sh --cachyos` does

1. **Trusts** the CachyOS master signing key (F3B607488DB35A47) via
   `pacman-key --recv-keys` + `--lsign-key`.
2. **Installs** `cachyos-keyring`, `cachyos-mirrorlist`,
   `cachyos-v3-mirrorlist` directly from the upstream tarball
   (`https://mirror.cachyos.org/cachyos-repo.tar.xz`). We pacman -U the
   `.pkg.tar.zst` files only — the bundled `cachyos-repo.sh` is NOT
   executed (it assumes CachyOS-the-distro layout).
3. **Edits `/etc/pacman.conf`** idempotently: backs up to
   `/etc/pacman.conf.pre-cachyos`, then inserts four repo blocks ABOVE
   the first non-`[options]` repo section (which on Artix is `[system]`):
   ```ini
   [cachyos-v3]
   Include = /etc/pacman.d/cachyos-v3-mirrorlist

   [cachyos-core-v3]
   Include = /etc/pacman.d/cachyos-v3-mirrorlist

   [cachyos-extra-v3]
   Include = /etc/pacman.d/cachyos-v3-mirrorlist

   [cachyos]
   Include = /etc/pacman.d/cachyos-mirrorlist
   ```
4. **`pacman -Syy`** to resync, then the base bootstrap's `pacman -Syu`
   step pulls the v3 rebuilds in-place. (First-match-wins ordering means
   any package present in both CachyOS and Arch comes from CachyOS.)
5. **Installs `pkgs/cachyos.txt`** at the end of the script:
   `linux-cachyos` + `linux-cachyos-headers` + `ananicy-cpp-runit` +
   `cachyos-ananicy-rules-git`. nvidia-dkms rebuilds automatically via
   pacman's DKMS hook when the kernel installs.
6. **Runs `grub-mkconfig`** so the new kernel shows up at the GRUB menu.

## After `--cachyos` — verify

```sh
# Repo blocks present and synced:
pacman -Sl cachyos-v3 | head            # should list v3 packages
pacman -Q linux-cachyos linux-cachyos-headers
pacman -Q ananicy-cpp cachyos-ananicy-rules-git

# Pick the Cachy kernel at GRUB the first boot, then:
uname -r                                  # contains "cachyos"
zcat /proc/config.gz | grep -i bore       # BORE scheduler compiled in
nvidia-smi                                # DKMS rebuild succeeded
```

If `nvidia-smi` works under linux-cachyos, you're good. If it doesn't
boot, pick the previous kernel (or `linux-lts` if you uncommented it)
from GRUB's "Advanced options" submenu.

## Enabling ananicy-cpp

`bootstrap.sh` installs the package but does **not** enable the service
(it's a tuning daemon; you should know it's running). To turn it on:

```sh
sudo ln -s /etc/runit/sv/ananicy-cpp /etc/runit/runsvdir/default/
# Within ~5s runsvdir picks it up:
sudo sv status ananicy-cpp
```

The CachyOS rules ship at `/etc/ananicy.d/00-default/` (or similar) and
are picked up automatically. Edit `/etc/ananicy-cpp.conf` if you want to
tweak global behavior.

## Manual extensions (NOT automated)

These are the parts that `cachyos-settings` would do for you on
CachyOS-the-distro. Doing them by hand on Artix avoids the systemd dep.

### sysctl drops

Drop a file at `/etc/sysctl.d/99-cachyos-tunings.conf` with the keys you
want; `sysctl --system` applies on next boot (or `sudo sysctl -p
/etc/sysctl.d/99-cachyos-tunings.conf` immediately).

Conservative starting point (mirror CachyOS's most impactful tunings):

```ini
# /etc/sysctl.d/99-cachyos-tunings.conf
# Better responsiveness under memory pressure:
vm.swappiness               = 100
vm.vfs_cache_pressure       = 50
vm.dirty_bytes              = 268435456
vm.dirty_background_bytes   =  67108864
vm.dirty_writeback_centisecs= 1500
vm.page-cluster             = 0
# Network buffer sizes for high-throughput workloads:
net.core.rmem_max           = 16777216
net.core.wmem_max           = 16777216
```

`vm.swappiness = 100` is correct only if you're using **zram** (see
below). On a no-zram system the safer value is 10–60.

### I/O scheduler per device class (udev)

Drop at `/etc/udev/rules.d/60-ioschedulers.rules`:

```udev
# NVMe SSDs: no queueing (the device queues internally).
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
# SATA SSDs: mq-deadline for low latency.
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# Rotational HDDs: bfq for fairness.
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
```

eudev picks it up at next boot, or `sudo udevadm control --reload &&
sudo udevadm trigger`.

### CPU governor as a runit service

A tiny one-shot service that sets `performance` (or `schedutil`) once at
boot. Make `/etc/runit/sv/cpu-governor/run`:

```sh
#!/bin/sh
# /etc/runit/sv/cpu-governor/run
exec 2>&1
# Use "schedutil" if you want CPU to scale down when idle.
GOV=performance
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  printf '%s\n' "$GOV" > "$f"
done
# Sleep forever so runit considers the service "up" (one-shot pattern).
exec sleep infinity
```

`chmod +x` the run script, then symlink into the runlevel:

```sh
sudo chmod +x /etc/runit/sv/cpu-governor/run
sudo ln -s /etc/runit/sv/cpu-governor /etc/runit/runsvdir/default/
```

For a desktop with reliable cooling, `performance` is the right call.
For lower idle wattage, `schedutil`.

### zram via Artix's zram-runit

If you want zram (compressed swap in RAM — almost free perf for builds
or running with lots of background tabs):

```sh
sudo pacman -S zram-runit
sudo ln -s /etc/runit/sv/zram /etc/runit/runsvdir/default/
```

Configure size in `/etc/conf.d/zram` (the Artix package ships a
commented sample). Half of RAM as `zstd`-compressed zram is the common
choice on a 64 GB box → 32 GB of swap that's actually fast.

If you set up zram, `vm.swappiness = 100` makes sense; otherwise lower it.

### scx-scheds runit service (optional)

`scx-scheds` provides userspace sched-ext schedulers. `linux-cachyos`
already has BORE + sched-ext baked in by default — running an `scx_*`
daemon on top is an additional layer, not required. Skip unless you
want to experiment.

If you do want it:

```sh
sudo pacman -S scx-scheds      # add to pkgs/cachyos.txt and re-bootstrap
sudo mkdir -p /etc/runit/sv/scx
```

`/etc/runit/sv/scx/run`:

```sh
#!/bin/sh
# /etc/runit/sv/scx/run
exec 2>&1
# Pick one: scx_lavd (latency-focused), scx_rusty (general), scx_bpfland (gaming).
exec scx_lavd
```

```sh
sudo chmod +x /etc/runit/sv/scx/run
sudo ln -s /etc/runit/sv/scx /etc/runit/runsvdir/default/
```

Stopping reverts to the kernel default scheduler. To switch schedulers,
edit the `run` script and `sudo sv restart scx`. Don't run multiple at
once.

## Maintenance gotchas

- **Every `pacman -Syu`**: skim the package list. If you ever see
  `systemd` in the transaction, abort and check which package is asking
  for it (`pacman -Si <pkg>`). It's almost never the v3 rebuild — it's
  usually a NEW dep on an updated tuning package. Pin that package back
  to Arch with `IgnorePkg = <pkg>` in `/etc/pacman.conf`.
- **Artix's natural seatbelt**: Artix's `[system]` repo doesn't ship
  `systemd`. If a CachyOS rebuild does depend on it, pacman fails with
  "unable to satisfy dependency: systemd" — that's the safety mechanism
  doing its job, not a bug. Read the error and pin around the package.
- **Kernel updates**: `linux-cachyos` updates pull a new kernel + DKMS
  rebuild. If `nvidia-dkms` fails the build (rare but happens on a new
  point release), reboot into `linux-lts` and `paru -Syu` once more
  later when the fix lands.
- **AUR + CachyOS**: paru still builds AUR packages against your
  *running* kernel headers. After a `linux-cachyos` update, log out and
  reboot before running `paru -Syua` so AUR builds match the headers
  you're about to use.

## Reverting the CachyOS layer

If you regret it:

```sh
# 1. Restore the pre-cachyos pacman.conf.
sudo mv /etc/pacman.conf.pre-cachyos /etc/pacman.conf
# 2. Remove the kernel + tuning packages.
sudo pacman -Rns linux-cachyos linux-cachyos-headers \
                 cachyos-ananicy-rules-git ananicy-cpp \
                 cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist
# 3. Resync and force-downgrade any v3 rebuilds back to Arch versions.
sudo pacman -Syyuu
# 4. Refresh GRUB to drop the Cachy kernel entry.
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

Step 3 is the slow one — `-uu` allows downgrades, and several hundred
packages will be replaced. Snapshot before doing this too.

## Sources

- CachyOS repo install (official): <https://wiki.cachyos.org/cachyos_repositories/how_to_add_cachyos_repo/>
- CachyOS sysctl tunings (reference, do NOT install as a package): <https://github.com/CachyOS/CachyOS-Settings>
- Artix ananicy-cpp-runit: <https://gitea.artixlinux.org/packagesA/ananicy-cpp-runit>
- BORE scheduler: <https://github.com/firelzrd/bore-scheduler>
- sched-ext + scx-scheds: <https://github.com/sched-ext/scx>
- Arch wiki — Improving performance: <https://wiki.archlinux.org/title/Improving_performance>
