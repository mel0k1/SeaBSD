# SeaBSD Build Framework

This directory contains the draft build framework for producing SeaBSD installation images from FreeBSD sources. It is a v0 scaffold: the overall pipeline shape is final, individual parameters will evolve as the first real builds happen.

## Pipeline overview

```text
FreeBSD src tree --> buildworld --> buildkernel (SEABSD) --> release/ISO --> overlay --> SeaBSD ISO
```

1. **fetch** — clone or update the FreeBSD source tree at a pinned branch/tag.
2. **world** — `make buildworld` against the base sources.
3. **kernel** — `make buildkernel` using the `SEABSD` kernel configuration from `build/kernel/`.
4. **iso** — assemble the release ISO via the FreeBSD release tooling.
5. **overlay** (TODO, v0.1) — apply `build/overlay/` on top of the assembled image: SeaBSD defaults, configuration snippets, branding.

## Requirements

- FreeBSD 14.x host (bare metal or virtual machine) — the scripts refuse to run elsewhere.
- Roughly 40 GB of free disk space for sources, objects and release artifacts.
- `git` available in the base system.

## Quick start

```sh
sh build/build-iso.sh           # run all stages: fetch, world, kernel, iso
sh build/build-iso.sh fetch     # run a single stage
sh build/build-kernel.sh build  # kernel only
```

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `SEABSD_FREEBSD_SRC` | `/usr/src` | Path to the FreeBSD source tree |
| `SEABSD_FREEBSD_BRANCH` | `release/14.3.0` | FreeBSD branch or tag to build from |
| `SEABSD_KERNCONF` | `SEABSD` | Kernel configuration name |
| `SEABSD_VERSION` | `0.0.1-snapshot` | SeaBSD version string used in build names |
| `SEABSD_CHROOTDIR` | `/var/tmp/seabsd-build` | Working directory for release builds |
| `SEABSD_SKIP_FETCH` | unset | Set to `1` to skip cloning/updating sources |

## Kernel configuration

`kernel/SEABSD` includes FreeBSD `GENERIC` and adds desktop-relevant options with comments explaining every change. The Linux compatibility layer does not need kernel configuration options — it is delivered by loadable modules enabled at runtime, which keeps the kernel config clean.

## Overlay mechanism

`overlay/` mirrors a filesystem tree that gets applied on top of the base system after installation. Current planned content and the roadmap for it are described in [overlay/README.md](overlay/README.md).

## Troubleshooting

- **`buildworld` fails with out-of-memory errors** — reduce parallelism: run with a lower `-j` value (see the `NPROC` computation in the scripts).
- **Release stage complains about missing ports** — the release tooling expects an up-to-date ports tree; this hook will be handled in v0.1 (tracked in ROADMAP).
- **Script refuses to run** — you are probably on Linux or macOS; use a FreeBSD VM (the CI smoke test shows how a FreeBSD environment is provisioned).
