# ext4 over Btrfs; no filesystem snapshot tooling

Decided 2026-05-23. Root filesystem is **ext4**, single mount at `/`, no
`/home` split, no `@`/`@home`/`@snapshots` subvolume layout, no snapper /
timeshift / snap-pac. Rollback is **(1)** the `linux-lts` boot entry in
GRUB for kernel-side failures and **(2)** Bazzite on disk 1 as the
fallback OS, with **(3)** re-running `install.sh + bootstrap.sh` as the
disaster-recovery plan — both scripts are idempotent and the package set
is in git, so rebuilding is ~30 minutes.

Btrfs was the original pick precisely so we could `btrfs subvolume
snapshot` before every `pacman -Syu`. Flipping to ext4 trades that
safety net for measurable raw-I/O performance (~5–15% on disk-bound
benchmarks; ~1–5% on real game-load times; CoW + checksumming + zstd
compression cost CPU per op) and a simpler mental model — one
filesystem, one root, no subvolume confusion in `df` / `du` / package
managers. The dual-disk-with-Bazzite-untouched layout makes the
snapshot story partly redundant: any catastrophic Artix breakage falls
back to Bazzite while we triage, so a snapshot-before-update workflow
defends mostly against the case where the box is bricked AND Bazzite
is unavailable, which is rare.

## Consequences

- `docs/05` no longer documents a snapshot-before-update ritual. The
  replacement ritual is: read Arch + Artix news, snapshot nothing,
  trust the linux-lts fallback boot entry, and keep Bazzite working.
- `docs/06` Cachy-layer "snapshot before upgrade" prereq is gone for
  the same reason; the Cachy kernel failure mode falls back to
  linux-lts in GRUB.
- `/home` is not on its own partition. Reinstalling the OS nukes
  `/home`. Mitigation: dotfiles live in git (when set up), Steam
  library is reinstalled from Steam, anything else important is on
  Bazzite or backed up off-box.
- `nvidia-dkms` builds against both `linux` and `linux-lts` because
  `linux-lts-headers` is in `pkgs/pacman.txt`.
