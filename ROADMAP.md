# SeaBSD Roadmap

Status legend: `[ ]` planned, `[~]` in progress, `[x]` done.

## v0.1.0 — "Harbor" (current focus)

Theme: prove the two pillars that define SeaBSD — **Linux compatibility** and **hardware awareness**. No desktop polish yet; this release is about the engine room.

### Linuxolator baseline

- [x] Select and document the target Linux userland for v0.1 — decision: Ubuntu 24.04 LTS (noble), pinned artifact, policy and alternatives in `docs/linux-base.md`
- [x] Build a compatibility test matrix script (`tools/linux-matrix.sh`) covering: browsers, Steam, media players, developer tools
- [ ] Audit syscall and library gaps found on the matrix; file upstream reports for each confirmed gap
- [ ] Package tuning: `/compat/linux` layout, procfs/fdescfs mount policy, audio bridge (ALSA to OSS) defaults
- [ ] CI job skeleton for linuxolator tests on a FreeBSD runner
- [ ] User documentation: "Running Linux applications on SeaBSD"

### Hardware support

- [ ] `tools/hwcheck.sh` v1: hardware inventory report (PCI, USB, network, kernel modules, audio)
- [ ] Compatibility database format (YAML) with first entries for Wi-Fi, GPUs and sound
- [ ] Compatibility matrix documentation, generated from the database
- [ ] Installer hardware-detection notes: detection to driver mapping to user-facing messages

### Infrastructure

- [x] Repository scaffold with CI (ShellCheck, markdown lint, structure check, FreeBSD smoke test, tag artifacts)
- [ ] Release engineering: source tarballs, changelog automation, signed tags

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
