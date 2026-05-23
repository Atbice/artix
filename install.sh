#!/bin/bash
# install.sh — declarative Artix Linux installer for this gaming box.
#
# Runs from the Artix dinit base ISO (artix-base-dinit-*.iso). Mirrors
# the runbook in docs/01-install-artix.md but as a single declarative
# pass: you pass the few real choices as flags, the rest are this
# repo's locked decisions (dinit, ext4 single root, two ESPs, GRUB
# --removable, dual-boot-safe). Rollback is "boot Bazzite, reinstall
# Artix" — there's no snapshot tooling. See docs/adr/0001 for why.
#
# Usage:
#   ./install.sh --disk /dev/nvme1n1 [options]
#
# Required:
#   --disk PATH        Target disk (will be WIPED). e.g. /dev/nvme1n1
#
# Optional (sensible defaults):
#   --hostname NAME    System hostname             (default: gamingbox)
#   --user NAME        Primary username            (default: bice)
#   --timezone TZ      tzdata entry                (default: Europe/Oslo)
#   --locale LOCALE    locale.gen line             (default: en_US.UTF-8)
#   --keymap KMAP      console keymap              (default: no-latin1)
#   --dry-run          Print actions, change nothing
#   --yes              Skip the "type INSTALL" confirmation
#
# Passwords for root + the new user are prompted for interactively
# (stty -echo); they are never read from argv or written to disk.
#
# After install completes: reboot, remove the USB, re-plug the other
# OS's disk (if you unplugged it), boot Artix on tty1 as the new user,
# clone this repo and run ./bootstrap.sh to provision the desktop
# (niri + Noctalia + NVIDIA + Steam + ...).
set -eu

DISK=""
HOSTNAME_=gamingbox
USERNAME_=bice
TIMEZONE=Europe/Oslo
LOCALE=en_US.UTF-8
KEYMAP=no-latin1
DRY=0
SKIP_CONFIRM=0

while [ $# -gt 0 ]; do
  case "$1" in
    --disk)     DISK="$2";       shift 2 ;;
    --hostname) HOSTNAME_="$2";  shift 2 ;;
    --user)     USERNAME_="$2";  shift 2 ;;
    --timezone) TIMEZONE="$2";   shift 2 ;;
    --locale)   LOCALE="$2";     shift 2 ;;
    --keymap)   KEYMAP="$2";     shift 2 ;;
    --dry-run)  DRY=1;           shift ;;
    --yes)      SKIP_CONFIRM=1;  shift ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1 (see --help)" >&2; exit 2 ;;
  esac
done

say()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n'  "$*" >&2; }
err()  { printf '\033[1;31m[X]\033[0m %s\n'  "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else sh -c "$*"; fi; }

# --- guard: Artix live ISO --------------------------------------------------
[ -r /etc/os-release ] && grep -q '^ID=artix' /etc/os-release \
  || err "not Artix (run from the artix-base-dinit weekly ISO)"
mount | grep -q ' on / type overlay' \
  || warn "/ isn't overlayfs — are you running this from an installed system instead of the live ISO?"

# --- guard: required args ---------------------------------------------------
if [ -z "$DISK" ]; then
  echo "missing --disk. Available block devices:" >&2
  lsblk -d -o NAME,SIZE,MODEL,SERIAL >&2
  exit 2
fi
[ -b "$DISK" ] || err "$DISK is not a block device"

# --- multi-disk warning (not a refusal) -------------------------------------
DISK_COUNT=$(lsblk -dn -o NAME | grep -cv '^loop\|^sr\|^zram' || true)
if [ "$DISK_COUNT" -gt 1 ]; then
  warn "$DISK_COUNT non-removable disks visible. docs/01 expects you to have PHYSICALLY unplugged the other OS's disk first."
  warn "Disks present:"
  lsblk -d -o NAME,SIZE,MODEL,SERIAL | sed 's/^/    /' >&2
fi

# --- partition-name prefix (NVMe/MMC uses pN; SATA uses N) ------------------
case "$DISK" in
  *nvme*|*mmcblk*) PART="${DISK}p" ;;
  *)               PART="${DISK}"  ;;
esac
ESP="${PART}1"
ROOTPART="${PART}2"

# --- plan + confirmation ----------------------------------------------------
say "Install plan (about to WIPE $DISK)"
cat <<EOF
  Target disk      : $DISK   (partitions: $ESP EFI, $ROOTPART ext4 /)
  Filesystem       : ext4 (single root, no /home split, no snapshot tooling)
  Init             : dinit (dinit + dinit-rc + elogind-dinit)
  Kernels          : linux (mainline) + linux-lts (boot fallback)
  Microcode        : amd-ucode (auto-loaded by GRUB at early boot)
  Networking       : NetworkManager + networkmanager-dinit (enabled in chroot)
  Swap             : zramen (compressed swap in RAM, enabled in chroot)
  Bootloader       : GRUB --removable (writes /EFI/BOOT/BOOTX64.EFI on ${DISK}'s ESP only — does NOT touch NVRAM)
  Hostname         : $HOSTNAME_
  Username         : $USERNAME_  (group: wheel, shell: /bin/bash)
  Timezone         : $TIMEZONE
  Locale           : $LOCALE
  Console keymap   : $KEYMAP
EOF
if [ "$SKIP_CONFIRM" = 0 ] && [ "$DRY" = 0 ]; then
  printf 'Type INSTALL to proceed (anything else aborts): '
  read -r confirm
  [ "$confirm" = "INSTALL" ] || err "aborted by user"
fi

# --- prompt for passwords (never via argv) ----------------------------------
ROOT_PW=""; USER_PW=""
if [ "$DRY" = 0 ]; then
  prompt_pw() {
    # prompt_pw <label> <var-name>
    local _label="$1" _varname="$2" _a="" _b=""
    while :; do
      printf '%s password: '       "$_label"; stty -echo; read -r _a; stty echo; printf '\n'
      printf '%s password (again): ' "$_label"; stty -echo; read -r _b; stty echo; printf '\n'
      [ "$_a" = "$_b" ] && [ -n "$_a" ] && break
      warn "passwords didn't match (or empty), try again"
    done
    eval "$_varname=\$_a"
  }
  prompt_pw "root"        ROOT_PW
  prompt_pw "$USERNAME_"  USER_PW
fi

# --- live-session keymap so the next prompts behave -------------------------
say "Setting live console keymap"
run "loadkeys $KEYMAP"

# --- partition -------------------------------------------------------------
say "Partitioning $DISK (512M EFI + remainder ext4)"
run "wipefs -af $DISK"
run "sgdisk --zap-all $DISK"
run "sgdisk -n 1:0:+512M -t 1:ef00 -c 1:EFI         $DISK"
run "sgdisk -n 2:0:0     -t 2:8300 -c 2:artix-root  $DISK"
run "partprobe $DISK"
[ "$DRY" = 0 ] && sleep 1

# --- format ----------------------------------------------------------------
say "Formatting"
run "mkfs.fat -F32 -n ARTIX-EFI $ESP"
run "mkfs.ext4 -F -L artix $ROOTPART"

# --- mount the install tree ------------------------------------------------
# Single root + ESP. noatime saves SSD write cycles (universal best practice
# on NVMe); we deliberately don't pass `discard` — continuous TRIM can cause
# game frame-time hitching. Use a weekly fstrim job instead if wanted.
say "Mounting the install tree"
run "mount -o noatime $ROOTPART /mnt"
run "mkdir -p /mnt/boot"
run "mount $ESP /mnt/boot"

# --- basestrap -------------------------------------------------------------
# Enough to boot Artix into a working TTY with network + zram + a fallback
# kernel, so bootstrap.sh can be cloned in on first boot. Desktop packages
# (niri, Noctalia, Steam, NVIDIA) are bootstrap.sh's job.
say "basestrap (Artix's pacstrap)"
run "basestrap /mnt \
                 base base-devel \
                 dinit dinit-rc elogind-dinit \
                 linux linux-lts linux-firmware \
                 amd-ucode \
                 networkmanager networkmanager-dinit \
                 zramen zramen-dinit \
                 grub efibootmgr \
                 git nano"

# --- fstab -----------------------------------------------------------------
say "Generating fstab (by UUID)"
run "fstabgen -U /mnt >> /mnt/etc/fstab"

# --- chroot config ---------------------------------------------------------
# Heredoc on stdin to artix-chroot. Avoids writing passwords to a script
# file on the new disk. Variables are expanded by THIS shell before the
# heredoc reaches the chroot, so they're already substituted in. Passwords
# go in via env so they never appear on argv / in /proc/*/cmdline.
say "Configuring inside artix-chroot (timezone, locale, hosts, hostname, users, sudoers, pacman, services, GRUB)"
if [ "$DRY" = 1 ]; then
  cat <<EOF
  [dry-run] artix-chroot /mnt /bin/bash <<'CHROOT_END'
  (timezone $TIMEZONE, locale $LOCALE, keymap $KEYMAP, hostname $HOSTNAME_,
   /etc/hosts entries, useradd -m -G wheel -s /bin/bash $USERNAME_,
   sudoers wheel uncomment, pacman.conf ParallelDownloads+Color+ILoveCandy,
   dinitctl --offline enable dbus elogind NetworkManager zramen,
   grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Artix --removable,
   grub-mkconfig -o /boot/grub/grub.cfg)
  CHROOT_END
EOF
else
  ROOT_PW="$ROOT_PW" USER_PW="$USER_PW" \
  artix-chroot /mnt /bin/bash <<CHROOT_END
set -eu

# timezone + hwclock
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# locale — uncomment if present, append if not
sed -i 's/^#\s*$LOCALE UTF-8/$LOCALE UTF-8/' /etc/locale.gen
grep -q '^$LOCALE UTF-8' /etc/locale.gen || echo '$LOCALE UTF-8' >> /etc/locale.gen
locale-gen
echo 'LANG=$LOCALE' > /etc/locale.conf

# console keymap
echo 'KEYMAP=$KEYMAP' > /etc/vconsole.conf

# hostname + /etc/hosts (sudo wants the hostname to resolve)
echo '$HOSTNAME_' > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME_.localdomain $HOSTNAME_
HOSTS

# root password
echo "root:\$ROOT_PW" | chpasswd

# primary user
useradd -m -G wheel -s /bin/bash '$USERNAME_'
echo "$USERNAME_:\$USER_PW" | chpasswd

# sudoers — uncomment %wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL\$/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# pacman ergonomics — parallel downloads, color, the candy progress bar
sed -i 's/^#\s*Color/Color/'                          /etc/pacman.conf
sed -i 's/^#\s*ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
grep -q '^ILoveCandy' /etc/pacman.conf || sed -i '/^Color/a ILoveCandy' /etc/pacman.conf

# enable services for first boot. dinit isn't PID 1 in this chroot, so we
# use --offline to just create the boot.d symlink (no attempt to start).
dinitctl --offline enable dbus
dinitctl --offline enable elogind
dinitctl --offline enable NetworkManager
dinitctl --offline enable zramen

# bootloader — only on THIS disk's ESP, no NVRAM entry (--removable).
# grub-mkconfig auto-detects amd-ucode.img and both kernels.
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Artix --removable
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_END
  unset ROOT_PW USER_PW
fi

# --- unmount + done --------------------------------------------------------
say "Unmounting"
run "umount -R /mnt"

say "Done — Artix is installed on $DISK."
cat <<EOF

Next:
  1. \`reboot\` and remove the USB stick.
  2. Power off, reconnect the other OS's disk (if you unplugged it).
  3. Tap the firmware boot menu (F11/F12/Esc) and pick Artix.
  4. Log in on tty1 as $USERNAME_.
  5. Clone this repo and run bootstrap.sh:
       sudo pacman -S git
       git clone <this repo> ~/artix && cd ~/artix
       ./bootstrap.sh
EOF
