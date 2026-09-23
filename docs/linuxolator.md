# SeaBSD Linuxolator Plan

## What the linuxolator is

The FreeBSD Linux compatibility layer (colloquially the *linuxolator*) allows unmodified Linux binaries to run on FreeBSD. The kernel exposes a Linux personality through loadable modules (`linux.ko` for 32-bit, `linux64.ko` for 64-bit) that intercept Linux system calls and translate them to native FreeBSD operations. Linux binaries find their shared libraries and supporting files under `/compat/linux`, populated by a "Linux base" package. There is no virtual machine and no emulation of CPU instructions involved — this is a syscall translation layer, which is why it can be both fast and fragile at the same time.

For SeaBSD this layer is a product surface, not a compatibility footnote. Most desktop applications ship as Linux binaries; the quality of the linuxolator experience therefore decides whether SeaBSD feels like a complete desktop or a curiosity.

## How it works today

- The layer is enabled at runtime (`linux_enable="YES"` in `rc.conf`) and mounts `linprocfs`, `linsysfs` and `tmpfs` views inside `/compat/linux` so Linux programs see a Linux-like `/proc` and `/sys`.
- The userland side is provided by a Linux base package. Historically that was CentOS-based (`linux_base-c7`); the ecosystem is moving toward Debian/Ubuntu-based bases, which are closer to what modern Linux software expects.
- Modern software is mostly static or dynamically linked against glibc with a large set of auxiliary libraries; missing libraries are the most common failure mode, followed by gaps in less-travelled syscalls and filesystem expectations.

## Current pain points

| Area | Problem | User-visible effect |
| --- | --- | --- |
| Syscall coverage | Occasional unimplemented or partial syscalls, especially around newer kernel interfaces | Applications crash or refuse to start with cryptic errors |
| `/proc` fidelity | `linprocfs` does not reproduce every Linux `/proc` behaviour | Diagnostics inside apps misreport; some launchers fail |
| Audio | Applications target ALSA/PulseAudio; FreeBSD audio is OSS | No sound or misrouted sound without manual configuration |
| Graphics | GPU acceleration depends on linuxkpi-backed DRM drivers; Vulkan paths vary | Games and browsers may fall back to software rendering |
| Packaging | Linux base composition is dictated by ports, not by the distribution | Hard to guarantee a tested, versioned userland |
| Diagnostics | When a Linux app fails, there is no standard way to capture why | Users cannot file useful bug reports |

## SeaBSD v0.1 plan

1. **Pick one tested base.** Select a single Linux base and freeze its composition. Decided: **Ubuntu 24.04 LTS (noble)**, pinned as `ubuntu-base-24.04.5-base-amd64.tar.gz` — full rationale, comparison of alternatives and the composition policy live in `docs/linux-base.md`. A versioned, reproducible base is more valuable than a broad but random one.
2. **Build the test matrix.** Create `tools/linux-matrix.sh` that installs and exercises a fixed list of applications (browsers, Steam, media players, developer tools) and records pass/fail plus failure details. The matrix runs on every FreeBSD-capable CI cycle.
3. **Audit the gaps.** For every matrix failure, classify the cause: missing library, syscall gap, `/proc` mismatch, audio, graphics. File upstream FreeBSD reports for kernel-level gaps and keep distribution-level fixes in our overlay.
4. **Tune the defaults.** Make the common case work with zero configuration: correct `/compat/linux` mounts, sensible audio bridging defaults, and a diagnostic command that captures a Linux application failure in a form useful for bug reports.
5. **Document for users.** Publish a plain-language guide: what works, what needs an extra step, what is known broken. Honesty here is a SeaBSD principle, not an option.

## Test matrix tooling (v0.1)

The matrix is implemented as two files:

- `tools/linux-matrix.tsv` — the matrix data: one probe per line, with name, category, whether the entry is optional, the binary to run, its arguments and the regex expected in the output. Categories: `base` (linuxolator sanity probes), `browsers`, `gaming`, `media`, `development`.
- `tools/linux-matrix.sh` — the runner. It verifies the environment (linux64 module, `/compat/linux` base, linprocfs mounts), executes every probe under a time limit, classifies results as `PASS` / `FAIL` / `TIMEOUT` / `SKIP` / `MISSING`, and writes a YAML report.

Usage on a FreeBSD system:

```sh
sh tools/linux-matrix.sh check               # environment diagnostics
sh tools/linux-matrix.sh list                # show the matrix
sh tools/linux-matrix.sh run                 # full run + report
sh tools/linux-matrix.sh --only base run     # linuxolator sanity probes only
sh tools/linux-matrix.sh --strict run        # treat MISSING entries as failures
```

The report (`dist/linux-matrix-report.yaml` by default) is designed to be attached to GitHub issues. `base` entries run first by design: if they fail, application-level failures are meaningless until the linuxolator itself is fixed. Optional entries that are simply not installed become `SKIP`, not `FAIL`, so a minimal system still produces a clean, meaningful report.

CI runs the `base` probes on every push: the `freebsd-linux-matrix` job boots a FreeBSD VM, installs the pinned base with `tools/fetch-linux-base.sh` and runs `--only base` (see `docs/linux-base.md` for the pinned artifact). This keeps a continuous, honest signal that the linuxolator itself works with the frozen userland.

## Success criteria for v0.1

- The full test matrix has recorded results with zero unexplained failures.
- Every application on the supported list launches from a default SeaBSD installation without manual configuration, or has a documented, explicit workaround.
- A user who hits a new failure can run one command and produce a report that a developer can act on.

## References

- FreeBSD manual page: `linux(4)`
- FreeBSD Wiki: Linux emulation / Linux container and application notes
- Upstream source: `sys/compat/linux/` in the FreeBSD source tree
