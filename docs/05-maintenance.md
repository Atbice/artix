# 05 — Rolling-release survival (the part Bazzite did for you)

You no longer have atomic image updates or one-command rollback. This is the
ongoing tax. Make it routine.

## Update ritual

```sh
sudo pacman -Syu           # official repos
paru -Sua                  # AUR upgrades — review PKGBUILDs when prompted
```

- **Read <https://artixlinux.org/news.php> and <https://archlinux.org/news/>
  before big updates.** Artix tracks Arch closely for most packages, so an
  Arch-side breaking-change post is almost always relevant. The textbook
  cases: `linux-firmware` splits, `pacman` keyring rotations,
  `glibc`/`libxcrypt` interactions.
- Skim the transaction summary before confirming. If `pacman` itself is in
  the list, finish that pass first, then re-run.
- Hold a package back: add to `IgnorePkg = ...` in `/etc/pacman.conf`, or
  use `paru --hold <pkg>` for AUR.
- **Never** run `paru -Sua` as root — `makepkg` refuses by design.

## Rollback story (without filesystem snapshots)

ext4 root, no snapshot tooling — see
[`docs/adr/0001-ext4-no-snapshots.md`](./adr/0001-ext4-no-snapshots.md)
for the trade. That makes rollback two layers, in this order:

1. **`linux-lts` fallback boot entry.** If a kernel update breaks nvidia
   or the boot path, pick `Advanced options for Artix → Artix Linux,
   with Linux linux-lts` from the GRUB menu. You're back in.
   `linux-lts-headers` is in `pkgs/pacman.txt` so nvidia-dkms also
   builds against it.
2. **Bazzite on disk 1.** If Artix dies completely, hold the firmware
   boot menu key (F11/F12/Esc) and pick Bazzite. You still have a
   working desktop while you triage. Worst case: re-run `install.sh` +
   `bootstrap.sh` on the new disk (`/home` is gone too — no separate
   partition).

The "fresh install in 30 minutes" story is real because both scripts
are idempotent and the package set is in git. Treat that as the
disaster-recovery plan and don't bolt a snapshot tool on top.

## NVIDIA + rolling kernel

- Driver is **DKMS-rebuilt** on kernel updates via pacman hooks (the
  `nvidia-dkms` package owns the hook). If a DKMS build fails you must be
  able to boot the old kernel.
- Keep **at least one fallback kernel** installed. The Arch/Artix default
  is to keep the running kernel + the new one; `linux-lts` is a cheap
  insurance policy (`sudo pacman -S linux-lts linux-lts-headers` adds it
  as an alternate boot entry).
- After a kernel or driver bump: reboot, then `nvidia-smi` before relying
  on the machine.
- Force a rebuild if needed: `sudo dkms autoinstall` then
  `sudo mkinitcpio -P`.

## AUR-specific risks

- AUR packages are user-submitted — `paru` shows the PKGBUILD diff before
  each upgrade. Read it; it's the only review step.
- `pkgs/aur.txt` currently only carries `faugus-launcher`; the heavy
  shell dependencies (Noctalia v5) live as a source build, not via AUR.

## Noctalia v5 (source build) — keeping it current

bootstrap.sh's section 7b clones the `v5` branch into
`~/src/noctalia-shell` and stamps `/usr/local/share/noctalia/.installed-sha`
after each successful build. Re-running `bootstrap.sh` does:

```sh
cd ~/src/noctalia-shell
git fetch origin v5 && git reset --hard origin/v5
# if HEAD changed since last install, rebuild + reinstall:
just configure release && just build release && sudo just install release
```

- **Breaking change after rebuild**: v5 is upstream-stamped as
  early-development. If the shell breaks after a `bootstrap.sh` pass,
  `git log --oneline -20` in `~/src/noctalia-shell` and pin to a
  known-good SHA: `git reset --hard <sha>` then rebuild.
- **Want to skip a bad day on upstream**: `touch
  ~/src/noctalia-shell/.skip-bootstrap` and add a guard to that section
  if you set this up frequently. (Out of scope right now; the manual
  pin-then-rebuild flow above is enough.)
- **Eventually**: when v5 lands on AUR, move it to `pkgs/aur.txt` and
  drop the source-build section + build deps. See
  [docs/03-shell-noctalia.md](./03-shell-noctalia.md) for the migration
  shape.

## Recovery toolkit (keep on a USB stick)

- **Artix install ISO** — same one you used in `docs/01`. Boot it, mount
  your root + ESP, `artix-chroot /mnt`, fix packages, regen initramfs
  (`mkinitcpio -P`), reinstall GRUB to disk 2's ESP. Same workflow as the
  install.
- **`linux-lts` boot entry in GRUB** — first line of defense for kernel
  / DKMS failures. install.sh installs it by default.
- **Bazzite on disk 1** — second line of defense. Boot from disk 1 (hold
  firmware boot key), use Artix's filesystem over SSH or via chroot from
  there.
- **Last line: `install.sh` + `bootstrap.sh`** — re-run the whole pair
  on the disk to rebuild from scratch in ~30 min. The package set is in
  git; the install is idempotent.

## What to keep in git (this repo) so the box is reproducible

- `pkgs/pacman.txt` and `pkgs/aur.txt` — regenerate the truth list anytime:
  ```sh
  pacman -Qqe | grep -vxF -f <(pacman -Qqm) > pkgs/installed-pacman.txt
  pacman -Qqm > pkgs/installed-aur.txt
  ```
  (`-Qqe` is explicitly installed; `-Qqm` is "foreign", i.e. AUR.)
- `services.txt` — dinit services you enabled (`dinitctl list` is the
  live truth; this file is the seed list bootstrap.sh re-applies).
- `etc/` — your `/etc/modprobe.d`, `/etc/mkinitcpio.conf.d`, `/etc/greetd`.
- Dotfiles live in a **separate chezmoi repo** (`chezmoi init --apply <repo>`),
  not here — keep provisioning and dotfiles decoupled.

Treat this repo as the source of truth: a dead disk → new disk, `docs/01`,
`./bootstrap.sh`, `chezmoi apply`, back in business.

## Sources

- Artix news: <https://artixlinux.org/news.php>
- Arch news (Artix tracks this): <https://archlinux.org/news/>
- Arch wiki — System maintenance: <https://wiki.archlinux.org/title/System_maintenance>
- Arch wiki — Pacman/Tips and tricks: <https://wiki.archlinux.org/title/Pacman/Tips_and_tricks>
- paru: <https://github.com/Morganamilo/paru>
