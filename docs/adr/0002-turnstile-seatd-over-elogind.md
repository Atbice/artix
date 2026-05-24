# turnstile + seatd over elogind for session/seat management

Decided 2026-05-24. Session and seat management on this box uses
**turnstile** (session daemon + logind D-Bus compatibility shim) and
**seatd** (low-level seat manager handling `/dev/dri` + `/dev/input`
access), not the more common **elogind**.

The driver is code provenance, not function: elogind works perfectly
well on Artix today, but its source lineage is systemd's
`src/login/`, forked and maintained independently by the Gentoo team
since ~2015. The rest of this stack (dinit, ext4, labwc, source-built
Noctalia v5) is explicitly chosen to have no systemd-derived code, and
elogind is the one component that breaks that pattern. turnstile +
seatd are from-scratch implementations of the same roles — turnstile
provides the org.freedesktop.login1 D-Bus interface that polkit,
NetworkManager, and the Wayland session expect; seatd hands out seat
ownership to whoever's at the seat. Both are packaged in Artix's main
repos with `-dinit` service variants. The combination is the canonical
"no-systemd-DNA" answer on a modern Wayland desktop.

## Consequences

- `install.sh` basestrap installs `seatd seatd-dinit turnstile
  turnstile-dinit` instead of `elogind-dinit`. The chroot enables
  `seatd` before `turnstile` because turnstile reads seat state from
  seatd's socket.
- `services.txt` lists `seatd` and `turnstile` instead of `elogind`.
- `pkgs/pacman.txt` carries both packages + their `-dinit` variants.
- labwc speaks libseat, which auto-detects seatd at runtime — no
  recompile needed.
- `bootstrap.sh` (post-install) doesn't touch the seat/session stack;
  the install-time chroot already enabled it.

## Risks accepted

- **turnstile is pre-1.0** (Artix ships 0.1.11). The Chimera Linux
  team daily-drives this combo, but on Chimera, not Artix — we're the
  test case for this exact distro + stack combination (Artix + dinit
  + turnstile + seatd + labwc + Noctalia v5 + NVIDIA).
- **Upstream is quiet**: last commit on `chimera-linux/turnstile` was
  2025-10-06 (~7 months before this decision). Not dormant, but not
  rapidly improving either. If upstream goes fully dormant and a
  logind D-Bus consumer demands behavior turnstile doesn't yet
  implement, the fallback is elogind.
- **Polkit / NetworkManager / sleep+idle edge cases** are the
  most-likely failure surfaces — anything that calls into the logind
  D-Bus methods expecting systemd-side semantics. Symptoms would be
  subtle (a polkit prompt not firing, NM seeing the session as
  inactive). Each is a real-time triage when it happens, not a
  blocker up front.

## Swap-back recipe (if turnstile breaks badly)

Five lines on Artix:

1. `pkgs/pacman.txt`: replace `seatd seatd-dinit turnstile
   turnstile-dinit` with `elogind elogind-dinit`.
2. `install.sh` basestrap: same swap.
3. `install.sh` chroot enables: replace `dinitctl --offline enable
   seatd && dinitctl --offline enable turnstile` with a single
   `dinitctl --offline enable elogind`.
4. `services.txt`: `seatd` + `turnstile` lines → `elogind`.
5. Reinstall (or `pacman -Rns turnstile turnstile-dinit seatd
   seatd-dinit && pacman -S elogind elogind-dinit && dinitctl enable
   elogind` on a live box).

Takes ~10 minutes on a working box. Worth keeping the option open.
