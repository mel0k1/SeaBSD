# SeaBSD

> **The BSD that works for people — not just for servers.**

[![CI](https://github.com/mel0k1/SeaBSD/actions/workflows/ci.yml/badge.svg)](https://github.com/mel0k1/SeaBSD/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)
![Status: pre-alpha](https://img.shields.io/badge/status-pre--alpha-orange)

**[Русская версия](README.ru.md)**

SeaBSD is a desktop-first operating system built on the foundations of [FreeBSD](https://www.freebsd.org). The project starts from a simple observation: BSD descendants are famously reliable as servers, yet almost nobody ships them to ordinary desktop users. SeaBSD flips the priorities — the same rock-solid base, tuned for laptops, workstations and everyday computing.

## Why SeaBSD?

FreeBSD already does the hard parts: a coherent base system, ZFS, Jails, a clean network stack and a source tree you can build end-to-end. What is missing is the user-facing layer. SeaBSD focuses on three pillars:

1. **Hardware that just works.** Automatic detection, a maintained compatibility database and honest documentation of what works out of the box — Wi-Fi, GPUs, sound, webcams.
2. **Linux software, better.** The FreeBSD Linux compatibility layer (the *linuxolator*) is powerful but rough on the edges. SeaBSD invests in testing, tuning and packaging so that Linux applications behave like first-class citizens instead of an afterthought.
3. **Resilient sandboxes.** Later releases will make disposable environments cheap: reset a broken sandbox to a clean state in seconds via ZFS snapshots, without redoing any setup.

## Project status

SeaBSD is in a **pre-alpha scaffolding stage**. The repository currently contains the project charter, roadmap, build framework drafts and CI. There is no installable image yet — the first milestone is described in [ROADMAP.md](ROADMAP.md).

## Documentation

| Document | Description |
| --- | --- |
| [VISION.md](VISION.md) | Mission, principles and non-goals of the project |
| [ROADMAP.md](ROADMAP.md) | Versioned roadmap: v0.1 "Harbor" and beyond |
| [docs/linuxolator.md](docs/linuxolator.md) | Plan for improving Linux application compatibility |
| [docs/hardware-support.md](docs/hardware-support.md) | Hardware detection and compatibility database plan |
| [build/README.md](build/README.md) | How to build SeaBSD images from FreeBSD sources |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development setup, code style and commit conventions |

## Building from source

Building a SeaBSD image requires a FreeBSD 14.x host (or a FreeBSD virtual machine):

```sh
git clone https://github.com/mel0k1/SeaBSD.git
cd SeaBSD
sh build/build-iso.sh
```

See [build/README.md](build/README.md) for environment variables, disk space requirements and a description of every build stage.

## Contributing

Contributions are welcome at this early stage — especially:

- hardware reports from real machines (`tools/hwcheck.sh` on FreeBSD),
- linuxolator compatibility tests and bug triage,
- documentation, translations and design work.

Read [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

## License

SeaBSD is distributed under the terms of the **BSD 3-Clause License** — the same license used by FreeBSD upstream, so code can flow between the projects without friction. See [LICENSE](LICENSE).

## Acknowledgements

SeaBSD stands on the shoulders of the [FreeBSD Project](https://www.freebsd.org) and its contributors, as well as the broader BSD ecosystem. SeaBSD is an independent project and is not affiliated with The FreeBSD Foundation.
