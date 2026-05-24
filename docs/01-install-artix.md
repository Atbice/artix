# 01 — Artix Linux install (dual-boot on a separate disk)

Goal: clean Artix (dinit) install on **disk 2**, with **disk 1 (Bazzite)
physically disconnected during install**. Both OSes get their own ESP and
their own bootloader. The firmware boot menu picks between them. Nothing the
Artix installer does can ever touch Bazzite.

> This is the same disk-safety pattern the original Void plan used — the only
> things that change here are the installer ISO and the package manager.

## Why this layout

- **Separate disks** = blast-radius zero. The installer can't see disk 1, so
  it can't accidentally repartition, install a shared GRUB, or touch the
  Bazzite ESP.
- **Two ESPs** = no chainloading, no shared `/boot/efi`, no Grub-trying-to-
  manage-Bazzite. Each OS owns its own boot.
- **Firmware menu** (`F11`/`F12` at POST, or your board's equivalent) picks
  the disk to boot — much more robust than os-prober and survives BIOS
  updates / NVRAM resets in a predictable way.

## Before you start

1. **Power off**, open the case, **physically unplug Bazzite's disk** (SATA
   or M.2). Yes, really. NVMe: unscrew it. SATA: pull the data cable.
2. Confirm disk 1 is gone in BIOS (`Setup → Storage`). Only disk 2 and any
   removable media should appear.
3. USB stick flashed with the **Artix dinit base ISO** — specifically the
   **weekly** variant (`artix-base-dinit-YYYYMMDD-x86_64.iso` from the
   "Weekly ISO images" section at <https://artixlinux.org/download.php>).
   The stable ISO has been known to fail for manual / scripted installs;
   the weekly is the supported path. The "base" variant ships only a TTY;
   we install the desktop ourselves via the bootstrap script.

## Install — scripted (recommended)

`install.sh` at the repo root automates everything below. It's
declarative: flag-driven, prompts only for passwords (never read from
argv), prints a confirmation summary before any destructive operation,
and warns (without refusing) if more than one disk is visible.

From the live ISO TTY:

```sh
# 1. Connect to network (nmtui or connmanctl), then:
pacman -Sy --noconfirm git
git clone https://github.com/Atbice/artix.git /root/artix
cd /root/artix

# 2. List your disks, identify the target:
lsblk -d -o NAME,SIZE,MODEL,SERIAL

# 3. Run with the locked defaults (gamingbox / bice / Europe/Oslo /
#    en_US.UTF-8 / no-latin1 keymap). Override any with flags.
./install.sh --disk /dev/nvme1n1
```

`./install.sh --help` prints the full flag list. `--dry-run` shows
every command without touching anything. `--yes` skips the "type
INSTALL" confirmation (for fully automated rebuilds).

The script does exactly what the "Manual install" section below
describes, in the same order. Skip ahead to **Plug disk 1 back in**
after it finishes; if you'd rather understand each step or `install.sh`
fails partway, the manual procedure stays here as the canonical
fallback.

## Manual install (fallback — terse; full handbook at <https://wiki.artixlinux.org/Main/Installation>)

1. Boot the ISO, log in as `artix` / `artix`.
2. `loadkeys <your-layout>` (e.g. `loadkeys no-latin1` for Norwegian).
3. Network: `connmanctl` or `nmtui` (NetworkManager is on the ISO).
4. Partition **disk 2 only** — verify with `lsblk` first, target should look
   like `/dev/nvme1n1` or similar. Layout (UEFI):
   ```
   /dev/nvme1n1p1   512M   EFI System (FAT32)    → mounted at /boot
   /dev/nvme1n1p2   *      Linux filesystem (ext4) → mounted at /
   ```
   No swap partition; we use `zramen` (compressed swap in RAM) instead —
   set up by install.sh / basestrap below. No `/home` split — single root.
   See `docs/adr/0001-ext4-no-snapshots.md` for why ext4 over Btrfs.
5. Format + mount:
   ```sh
   mkfs.fat -F32 /dev/nvme1n1p1
   mkfs.ext4 -L artix /dev/nvme1n1p2
   mount -o noatime /dev/nvme1n1p2 /mnt
   mkdir -p /mnt/boot
   mount /dev/nvme1n1p1 /mnt/boot
   ```
6. `basestrap /mnt base base-devel dinit dinit-rc seatd seatd-dinit turnstile turnstile-dinit linux linux-lts linux-firmware amd-ucode networkmanager networkmanager-dinit zramen zramen-dinit grub efibootmgr git nano`
   (`basestrap` is Artix's `pacstrap` equivalent. `dinit` is the daemon;
   `dinit-rc` is the boot scripts metapackage; `seatd` + `turnstile`
   replace elogind for session/seat management — see
   `docs/adr/0002`; `amd-ucode` is loaded by GRUB at early boot for the
   5900X; `linux-lts` is the safety-net kernel.)
7. `fstabgen -U /mnt >> /mnt/etc/fstab`
8. `artix-chroot /mnt`
9. Timezone, locale, hostname, root password, **make a normal user** and add
   to `wheel`:
   ```sh
   ln -sf /usr/share/zoneinfo/Europe/Oslo /etc/localtime
   hwclock --systohc
   echo en_US.UTF-8 UTF-8 >> /etc/locale.gen && locale-gen
   echo LANG=en_US.UTF-8 > /etc/locale.conf
   echo KEYMAP=no-latin1 > /etc/vconsole.conf
   echo gamingbox > /etc/hostname        # whatever you like
   cat > /etc/hosts <<EOF
   127.0.0.1   localhost
   ::1         localhost
   127.0.1.1   gamingbox.localdomain gamingbox
   EOF
   passwd
   useradd -m -G wheel -s /bin/bash bice  # change `bice` to your username
   passwd bice
   # uncomment "%wheel ALL=(ALL:ALL) ALL" in /etc/sudoers via `visudo`
   # Enable services for first boot (offline = create the boot.d symlink only).
   # Order matters: seatd before turnstile (turnstile reads seats from seatd):
   dinitctl --offline enable dbus
   dinitctl --offline enable seatd
   dinitctl --offline enable turnstile
   dinitctl --offline enable NetworkManager
   dinitctl --offline enable zramen
   ```
   (You'll switch to fish later — bootstrap doesn't change the login shell.)
10. Bootloader on **this disk only** (already installed via basestrap):
    ```sh
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Artix --removable
    grub-mkconfig -o /boot/grub/grub.cfg
    ```
    The `--removable` flag writes to `/boot/EFI/BOOT/BOOTX64.EFI` (the
    fallback path the firmware always looks at), so this survives NVRAM
    wipes and doesn't require an NVRAM entry that could collide with
    Bazzite's. The `efibootmgr` package is still useful for inspection.
11. `exit`; `umount -R /mnt`; `reboot` and remove the USB.

Confirm Artix boots and you have a TTY.

## Plug disk 1 back in

1. Power off. Reconnect Bazzite's disk.
2. Power on. **Tap the firmware boot-menu key** (`F11`/`F12`/`Esc` — depends
   on the board). You should see *both* "Bazzite" and "Artix" entries.
   Picking either should boot that OS cleanly.
3. Optionally set the firmware's default boot order — but **do not** install
   a shared GRUB, and do not run `os-prober` on either OS.

## Next

Clone this repo into your home dir on the Artix box and run the bootstrap:

```sh
sudo pacman -S git
git clone https://github.com/Atbice/artix.git ~/artix && cd ~/artix
./bootstrap.sh   # see README.md for flags
```

After bootstrap finishes and you reboot, you'll land in tuigreet → labwc.
Continue with [`02-nvidia-labwc.md`](./02-nvidia-labwc.md) to verify the
NVIDIA + labwc setup, then [`03-shell-noctalia.md`](./03-shell-noctalia.md)
for the Noctalia v5 shell (source-built).
