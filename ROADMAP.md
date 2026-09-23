# SeaBSD Roadmap

Status legend: `[ ]` planned, `[~]` in progress, `[x]` done.

## v0.1.0 — "Harbor" (current focus)

Theme: prove the two pillars that define SeaBSD — **Linux compatibility** and **hardware awareness**. No desktop polish yet; this release is about the engine room.

### Linuxolator baseline

- [x] Select and document the target Linux userland for v0.1 — decision: Ubuntu 24.04 LTS (noble), pinned artifact, policy and alternatives in `docs/linux-base.md`
- [x] Build a compatibility test matrix script (`tools/linux-matrix.sh`) covering: browsers, Steam, media players, developer tools
- [ ] Audit syscall and library gaps found on the matrix; file upstream reports for each confirmed gap
- [x] Futex stress probe and diagnostics tooling: `tools/probes/futex_stress.c`, `tools/futex-diag.sh`, plan in `docs/futex.md`
- [x] Run the futex probe on FreeBSD runners and classify results — done: 7/8 PASS; findings: plain `FUTEX_REQUEUE` fails on 14.1 (`requeue_nc`, first matrix-found syscall gap, upstream report pending), `futex_waitv` absent on 14.1 (SKIP); details in `docs/futex.md`
- [ ] File the plain `FUTEX_REQUEUE` finding upstream (errno capture already in the probe) and track it per `kernel-patches/README.md` if not fixed upstream quickly
- [ ] Audit the futex surfaces the probe does not cover yet: priority-inheritance family, robust lists, `FUTEX_WAKE_OP`
- [ ] Package tuning: `/compat/linux` layout, procfs/fdescfs mount policy, audio bridge (ALSA to OSS) defaults
- [x] CI job skeleton for linuxolator tests on a FreeBSD runner (boot VM + pinned base + `base` probes; futex category added)
- [ ] User documentation: "Running Linux applications on SeaBSD"

### Hardware support

- [ ] `tools/hwcheck.sh` v1: hardware inventory report (PCI, USB, network, kernel modules, audio)
- [ ] Compatibility database format (YAML) with first entries for Wi-Fi, GPUs and sound
- [ ] Compatibility matrix documentation, generated from the database
- [ ] Installer hardware-detection notes: detection to driver mapping to user-facing messages

### Infrastructure

- [x] Repository scaffold with CI (ShellCheck, markdown lint, structure check, FreeBSD smoke test, tag artifacts)
- [ ] Release engineering: source tarballs, changelog automation, signed tags

## Gap analysis (2026-09-24 review)

Result of a full codebase review after the futex tooling landed. Prioritized; P1 feeds v0.1, P2 feeds v0.2.

### P1 — closes v0.1

- **Application-level matrix is empty.** Only `base` and `futex` categories actually run; browsers/steam/media/development entries are all SKIP because packages are never installed into the pinned base. Need `tools/install-app-pkgs.sh` (apt inside the frozen noble base) + a CI stage or documented manual run.
- **No regression baseline.** Matrix reports are written per run but never compared against the previous run. Store a baseline YAML per runner and diff it (new FAIL vs baseline = loud signal; known-SKIP = quiet).
- **Futex risk zones are unmeasured.** PI family, robust lists and `FUTEX_WAKE_OP` have no probes yet (see `docs/futex.md`, risk zones).
- **vmactions/freebsd-vm is fragile.** Two VM jobs boot per push and one already died once on an image change (openrsync incident). Pin explicit runner images, add a retry, and evaluate a prebuilt VM snapshot if flakes continue.
- **Hardware track is paper-only.** `tools/hwcheck.sh` exists but the compatibility database has no entries and no lookup tool; nothing maps hwcheck output to `docs/hardware-support.md` YAML yet.
- **Build track is untested.** `build/build-iso.sh` / `build/build-kernel.sh` have never executed (they need a FreeBSD host + source fetch); at minimum add a VM smoke stage that runs `build-kernel.sh` argument validation, and document the manual build.
- **User guide missing.** "Running Linux applications on SeaBSD" (roadmap item) — the honest-what-works doc promised by VISION.

### P2 — hardening, feeds v0.2

- **TSV schema validation.** `structure-check.sh` could validate matrix line format (field count, category enum, optional flag) instead of trusting the data file.
- **Release engineering.** Changelog automation, signed tags, release checklist (source tarball job exists only for `v*` tags).
- **SECURITY.md** with a private vulnerability reporting path.
- **JSON report option** for the matrix (YAML-only today) for easier machine diffing; per-run history page.
- **Man pages / `--help` parity** for tools (matrix and fetch have help; hwcheck/structure-check do not).
- **Kernel patch application step** in `build/build-kernel.sh` over `kernel-patches/*/series` (referenced by `kernel-patches/README.md`).
- **EN/RU parity** for new user-facing docs (READMEs are bilingual; docs/*.md are EN-only).

## v0.2.0 — "Lighthouse"

Theme: **resilient sandboxes**. Environments that can be destroyed and rebuilt without losing user data or setup work.

- [ ] Sandbox layout on ZFS datasets: per-application datasets, snapshot on entry
- [ ] One-command reset (`seabsd-sandbox reset`) that rolls the system layer back to a snapshot while preserving user data volumes
- [ ] Sandbox templates: common profiles (browser, gaming, development) prebuilt and cached
- [ ] Prototype GUI toggle for sandbox state and reset

## v0.3.0 — "Fleet"

Theme: **desktop UX**. Bring the engine room to the user.

- [ ] Installer that shows the hardware report and compatibility status before install
- [ ] Preconfigured desktop environment (candidate: Xfce; evaluation: KDE Plasma) with SeaBSD defaults
- [ ] Software center front-end covering pkg packages and linuxolator applications
- [ ] First-boot wizard: user creation, updates, optional third-party components

## v1.0.0 — "Open Sea"

- [ ] First stable release: signed ISO, documented upgrade path, LTS-style support window
- [ ] Compatibility database mature enough to power installer warnings automatically
- [ ] linuxolator matrix at 100% pass rate for the supported application list
