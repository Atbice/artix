# 01 — Artix Linux install (dual-boot on a separate disk)

Goal: clean Artix (runit) install on **disk 2**, with **disk 1 (Bazzite)
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
3. USB stick flashed with the **Artix runit base ISO**
   (`artix-base-runit-*.iso`) from <https://artixlinux.org/download.php>. The
   "base" variant ships only a TTY; we install the desktop ourselves via the
   bootstrap script — that's the whole point of this repo.

## Install (terse — full handbook is at <https://wiki.artixlinux.org/Main/Installation>)

1. Boot the ISO, log in as `artix` / `artix`.
2. `loadkeys <your-layout>` (e.g. `loadkeys no-latin1` for Norwegian).
3. Network: `connmanctl` or `nmtui` (NetworkManager is on the ISO).
4. Partition **disk 2 only** — verify with `lsblk` first, target should look
   like `/dev/nvme1n1` or similar. Suggested layout (UEFI):
   ```
   /dev/nvme1n1p1   512M   EFI System (FAT32)     → mounted at /boot
   /dev/nvme1n1p2   *      Linux filesystem (Btrfs) → mounted at /
   ```
   No swap partition; a swapfile on Btrfs is fine if you ever need one.
5. Format + mount:
   ```sh
   mkfs.fat -F32 /dev/nvme1n1p1
   mkfs.btrfs -L artix /dev/nvme1n1p2
   mount /dev/nvme1n1p2 /mnt
   btrfs subvolume create /mnt/@
   btrfs subvolume create /mnt/@home
   btrfs subvolume create /mnt/@snapshots
   umount /mnt
   mount -o noatime,compress=zstd,subvol=@           /dev/nvme1n1p2 /mnt
   mkdir -p /mnt/{boot,home,.snapshots}
   mount -o noatime,compress=zstd,subvol=@home       /dev/nvme1n1p2 /mnt/home
   mount -o noatime,compress=zstd,subvol=@snapshots  /dev/nvme1n1p2 /mnt/.snapshots
   mount /dev/nvme1n1p1 /mnt/boot
   ```
6. `basestrap /mnt base base-devel runit elogind-runit linux linux-firmware nano`
   (`basestrap` is Artix's `pacstrap` equivalent.)
7. `fstabgen -U /mnt >> /mnt/etc/fstab`
8. `artix-chroot /mnt`
9. Timezone, locale, hostname, root password, **make a normal user** and add
   to `wheel`:
   ```sh
   ln -sf /usr/share/zoneinfo/Europe/Oslo /etc/localtime
   echo en_US.UTF-8 UTF-8 >> /etc/locale.gen && locale-gen
   echo LANG=en_US.UTF-8 > /etc/locale.conf
   echo gamingbox > /etc/hostname        # whatever you like
   passwd
   useradd -m -G wheel -s /bin/bash bice  # change `bice` to your username
   passwd bice
   # uncomment "%wheel ALL=(ALL:ALL) ALL" in /etc/sudoers via `visudo`
   ```
   (You'll switch to fish later — bootstrap doesn't change the login shell.)
10. Bootloader on **this disk only**:
    ```sh
    pacman -S grub efibootmgr
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
git clone <this repo> ~/void && cd ~/void
./bootstrap.sh   # see README.md for flags
```

After bootstrap finishes and you reboot, you'll land in tuigreet → niri.
Continue with [`02-nvidia-niri.md`](./02-nvidia-niri.md) to verify the
NVIDIA + niri setup, then [`03-shell-noctalia.md`](./03-shell-noctalia.md)
for the desktop shell.
