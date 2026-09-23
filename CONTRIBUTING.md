# Contributing to SeaBSD

Thanks for your interest in the project. SeaBSD is young, so the fastest way to help is also the simplest: run things on real hardware, report what happens, and keep the documentation honest. This document explains the practical rules for doing that well.

## Repository layout

| Path | Purpose |
| --- | --- |
| `build/` | Image build framework: ISO and kernel build scripts, kernel configuration, filesystem overlay |
| `docs/` | Engineering documents: linuxolator plan, hardware support plan |
| `tools/` | Developer and user tools: repository checks, hardware reporting |

## Development setup

- Documentation-only changes can be made from any operating system that has git.
- Shell scripts run anywhere a POSIX shell exists; CI enforces `sh -n` syntax checks and ShellCheck on every script.
- Building images requires a FreeBSD 14.x host or virtual machine. See [build/README.md](build/README.md) for requirements and environment variables.

## Code style

- Shell scripts are POSIX `/bin/sh`: no bashisms, no arrays, no `local`. Use `set -eu` in every script.
- Two-space indentation; every script starts with a comment explaining its purpose.
- Every script must pass `shellcheck -x` and `sh -n` locally before pushing.
- Kernel configuration edits must include a comment explaining *why* the option is there, not just what it does.
- User-facing changes to the front page must be reflected in both `README.md` (English) and `README.ru.md` (Russian). Internal `docs/` pages are English-first.

## Commit messages

Use the format `type: short summary`, where type is one of `docs`, `build`, `tools`, `ci`, `feat`, `fix`.

Examples:

```text
docs: add linuxolator test matrix draft
build: add KERNCONF override to build-kernel.sh
```

## Pull requests

1. Create a topic branch; keep one logical change per pull request where practical.
2. Make sure CI is green before requesting review.
3. Describe what was tested, and on which hardware, if the change is hardware-related.
4. If the pull request changes project direction, link to a discussion in an issue first — big decisions belong in the open.

## Reporting hardware results

This is the highest-value contribution right now. Run the inventory tool on a FreeBSD system:

```sh
sh tools/hwcheck.sh > hwreport.txt
```

Then open an issue and attach the report, stating clearly what works and what does not (Wi-Fi, sound, suspend, GPU acceleration). Reports feed the compatibility database described in [docs/hardware-support.md](docs/hardware-support.md).

## Running the linuxolator compatibility matrix

If you have a FreeBSD system (or SeaBSD itself), run the Linux application compatibility matrix and attach the report to a GitHub issue:

```sh
sh tools/linux-matrix.sh check   # environment diagnostics first
sh tools/linux-matrix.sh run     # full run, report in dist/linux-matrix-report.yaml
```

Results are classified as `PASS`, `FAIL`, `TIMEOUT`, `SKIP` or `MISSING` — the meaning of each status is documented in [docs/linuxolator.md](docs/linuxolator.md). Both green and red reports are valuable: they feed directly into the v0.1 linuxolator audit.

## License

By contributing you agree that your contributions are licensed under the BSD 3-Clause License, matching the [LICENSE](LICENSE) of the project.
