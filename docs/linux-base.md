# SeaBSD Linux Base — Decision Record

- **Status:** accepted (v0.1)
- **Decision:** Ubuntu 24.04 LTS ("noble"), minimal base (minbase rootfs), amd64
- **Pinned artifact:** `ubuntu-base-24.04.5-base-amd64.tar.gz`
- **Verified:** 2026-09-23

## The pinned artifact

| Field | Value |
| --- | --- |
| URL | https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.5-base-amd64.tar.gz |
| SHA256 | e77b6f10c2590cef872b33ee9f635a0e3fd1f57fb074c0e52b5c7f56147a0c86 |
| Size | 30028293 bytes |
| Upstream | Ubuntu Base (official minimal rootfs), 24.04.5 point release |
| glibc | 2.39 |
| Layout | merged /usr (`/bin -> usr/bin`) |

The exact combination of URL and SHA256 above is the frozen v0.1 base. `tools/fetch-linux-base.sh` embeds these values as defaults, so every SeaBSD build and every CI run unpacks byte-identical userland.

## Why a frozen base at all

The linuxolator translates syscalls in the kernel, but everything else a Linux application sees comes from the userland mounted under `/compat/linux`. If that userland drifts — different glibc here, extra libraries there — bug reports become unreproducible and the compatibility matrix measures noise. A single pinned base makes "works on SeaBSD" a verifiable statement instead of an anecdote.

## Alternatives considered

| Option | Verdict | Reasoning |
| --- | --- | --- |
| `linux_base-c7` (CentOS 7, ports default) | rejected | Battle-tested with the linuxolator, but glibc 2.17 predates most modern Linux binaries; CentOS 7 is EOL, so the base cannot even receive security updates. Shipping it to desktop users contradicts the SeaBSD principles. |
| Ubuntu 22.04 LTS ("jammy", initial candidate) | rejected for v0.1 | Strong community precedent and good linuxolator documentation, but standard support ends in April 2027 — too soon for a base frozen during v0.x. glibc 2.35 is sufficient yet not ideal for the newest Electron/game binaries. |
| Debian stable rootfs | rejected | No significant advantage over Ubuntu base for our use case; smaller community overlap with existing FreeBSD linuxolator tooling. |
| **Ubuntu 24.04 LTS ("noble")** | **accepted** | LTS support window to April 2029 (beyond v0.1 and v0.2), glibc 2.39 covers essentially all current Linux desktop binaries, official minimal rootfs is small (30 MB), and the base is distro-clean for apt-based extension. |

The one honest caveat: community-tested linuxolator userlands historically targeted CentOS/jammy, so noble is the least *conventionally* tested option. This is exactly what the SeaBSD compatibility matrix exists to measure — the v0.1 audit runs against the pinned noble base, and any linuxolator-level gaps we find get filed upstream.

## What the pinned base contains

The Ubuntu Base minbase rootfs was inspected at pin time:

- **Present:** `/usr/bin/ls`, `/usr/bin/bash`, `/usr/bin/ldd`, `/etc/os-release`, `libc.so.6` — everything the matrix `base` probes need to verify the linuxolator itself.
- **Absent (by design):** compilers, interpreters, browsers, media tools. The matrix marks those probes `optional`; they appear once the corresponding packages are added to the base by the packaging track.

## Base composition policy

1. **Freeze.** v0.1 ships exactly the pinned artifact above. No package is added to the default base without a change to this document.
2. **Point bumps.** Moving to a newer 24.04.x point release is allowed (and expected) whenever the full matrix is green on it; the URL and SHA256 here must be updated in the same commit.
3. **Major bumps.** Moving to a different LTS (or a different distribution) is a new decision record with a new comparison table — same process as this one.
4. **Extension, not mutation.** Application-specific libraries (game runtimes, browser deps) are layered on top of the base at install time rather than baked into it, so the base stays a single verifiable artifact.

## Known risks

- The linuxolator kernel layer predates some interfaces modern userlands expect (see `docs/linuxolator.md` pain-point table). The pinned glibc 2.39 will exercise syscall paths that CentOS-era bases never touched; gaps found here become the upstream audit list for v0.1.
- Ubuntu userland expects systemd; under the linuxolator we provide the needed pseudo-filesystem views (`linprocfs`, `linsysfs`) and do not run systemd at all. Applications that hard-require systemd are documented as unsupported.
- Security updates inside the base require rebuilding from a new point release — this is deliberate: updates are a build-time decision with a matrix gate, not an untracked drift.

## How to install the base

On a FreeBSD system:

```sh
sh tools/fetch-linux-base.sh               # download, verify SHA256, unpack to /compat/linux
sysrc linux_enable=YES                     # enable the linuxolator at boot
service linux start                        # load modules and mount /compat filesystems
sh tools/linux-matrix.sh --only base run   # verify: three PASS lines expected
```

The script is idempotent: it refuses to overwrite an existing base unless `--force` is given.
