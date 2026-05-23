#!/bin/bash
# install.sh — declarative Artix Linux installer for this gaming box.
#
# Runs from the Artix dinit base ISO (artix-base-dinit-*.iso). Mirrors
# the runbook in docs/01-install-artix.md but as a single declarative
# pass: you pass the few real choices as flags, the rest are this
# repo's locked decisions (dinit, Btrfs + 3 subvolumes, two ESPs, GRUB
# --removable, dual-boot-safe).
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
  Target disk      : $DISK   (partitions: $ESP EFI, $ROOTPART Btrfs)
  Subvolumes       : @ /, @home /home, @snapshots /.snapshots
  Init             : dinit (dinit + dinit-rc + elogind-dinit)
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
say "Partitioning $DISK (512M EFI + remainder Btrfs)"
run "wipefs -af $DISK"
run "sgdisk --zap-all $DISK"
run "sgdisk -n 1:0:+512M -t 1:ef00 -c 1:EFI         $DISK"
run "sgdisk -n 2:0:0     -t 2:8300 -c 2:artix-root  $DISK"
run "partprobe $DISK"
[ "$DRY" = 0 ] && sleep 1

# --- format ----------------------------------------------------------------
say "Formatting"
run "mkfs.fat -F32 -n ARTIX-EFI $ESP"
run "mkfs.btrfs -f -L artix $ROOTPART"

# --- subvolumes ------------------------------------------------------------
say "Creating Btrfs subvolumes (@, @home, @snapshots)"
run "mount $ROOTPART /mnt"
run "btrfs subvolume create /mnt/@"
run "btrfs subvolume create /mnt/@home"
run "btrfs subvolume create /mnt/@snapshots"
run "umount /mnt"

# --- mount the install tree ------------------------------------------------
MOUNT_OPTS="noatime,compress=zstd"
say "Mounting the install tree"
run "mount -o $MOUNT_OPTS,subvol=@           $ROOTPART /mnt"
run "mkdir -p /mnt/boot /mnt/home /mnt/.snapshots"
run "mount -o $MOUNT_OPTS,subvol=@home       $ROOTPART /mnt/home"
run "mount -o $MOUNT_OPTS,subvol=@snapshots  $ROOTPART /mnt/.snapshots"
run "mount $ESP /mnt/boot"

# --- basestrap -------------------------------------------------------------
# Bare minimum to boot Artix on dinit + GRUB + git (so bootstrap.sh can be
# cloned in on first boot). Desktop packages are bootstrap.sh's job.
say "basestrap (Artix's pacstrap)"
run "basestrap /mnt base base-devel dinit dinit-rc elogind-dinit \
                 linux linux-firmware \
                 grub efibootmgr \
                 git nano"

# --- fstab -----------------------------------------------------------------
say "Generating fstab (by UUID)"
run "fstabgen -U /mnt >> /mnt/etc/fstab"

# --- chroot config ---------------------------------------------------------
# Heredoc on stdin to artix-chroot. Avoids writing passwords to a script
# file on the new disk. Variables are expanded by THIS shell before the
# heredoc reaches the chroot, so they're already substituted in.
say "Configuring inside artix-chroot (timezone, locale, hostname, users, sudoers, GRUB)"
if [ "$DRY" = 1 ]; then
  cat <<EOF
  [dry-run] artix-chroot /mnt /bin/bash <<'CHROOT_END'
  (timezone $TIMEZONE, locale $LOCALE, keymap $KEYMAP, hostname $HOSTNAME_,
   useradd -m -G wheel -s /bin/bash $USERNAME_, sudoers wheel uncomment,
   grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Artix --removable,
   grub-mkconfig -o /boot/grub/grub.cfg)
  CHROOT_END
EOF
else
  # Export passwords to the chroot via env (NOT argv → not in /proc/*/cmdline).
  ROOT_PW="$ROOT_PW" USER_PW="$USER_PW" \
  artix-chroot /mnt /bin/bash <<CHROOT_END
set -eu

# timezone + hwclock
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# locale — uncomment the line if present, append it if not
sed -i 's/^#\s*$LOCALE UTF-8/$LOCALE UTF-8/' /etc/locale.gen
grep -q '^$LOCALE UTF-8' /etc/locale.gen || echo '$LOCALE UTF-8' >> /etc/locale.gen
locale-gen
echo 'LANG=$LOCALE' > /etc/locale.conf

# console keymap
echo 'KEYMAP=$KEYMAP' > /etc/vconsole.conf

# hostname
echo '$HOSTNAME_' > /etc/hostname

# root password
echo "root:\$ROOT_PW" | chpasswd

# primary user
useradd -m -G wheel -s /bin/bash '$USERNAME_'
echo "$USERNAME_:\$USER_PW" | chpasswd

# sudoers — uncomment %wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL\$/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# bootloader — only on THIS disk's ESP, no NVRAM entry (--removable)
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
