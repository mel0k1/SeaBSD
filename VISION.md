# SeaBSD Vision

## The problem

The BSD family is famous for engineering quality: a coherent base system, a clean network stack, ZFS, Jails, documentation that actually matches reality. And yet, if you hand a BSD installation disc to a regular computer user, the experience breaks down quickly: Wi-Fi may need manual configuration, graphics acceleration needs to be researched in wiki pages, popular applications (many of which only ship Linux binaries) require layers of compatibility setup, and when something breaks, there is rarely a clean way back.

Server operators accept this because servers are configured once, deliberately, by professionals. Desktop users do not live that way. They install, click, occasionally drop a file into a wrong folder, and expect the system to survive. A "BSD for users" has to be designed for that behaviour from the start, not patched onto a server philosophy afterwards.

## Mission

SeaBSD exists to bring the engineering quality of FreeBSD to people who never want to read `man rc.conf` just to get Wi-Fi working. The operating system should detect the machine, present a working desktop, run the software the user needs — including Linux software — and recover gracefully when things go wrong.

## Principles

1. **User-first defaults.** Every configuration decision is judged by one question: what would an ordinary non-expert user expect to happen? Expert knobs stay available, but never as the default path.
2. **Upstream-first.** Whenever an improvement belongs in FreeBSD itself (drivers, linuxolator fixes, installer pieces), we try to land it upstream before carrying a local patch. Long-term divergence is a maintenance debt we do not want.
3. **Honesty about hardware.** The compatibility database states reality, not marketing. If a Wi-Fi chip does not work, the installer should say so before installation, not after. Good hardware documentation is a feature, not a footnote.
4. **The Linux world is an asset, not an enemy.** Most desktop applications ship for Linux today. Instead of pretending otherwise, SeaBSD treats the Linux compatibility layer as a product surface: tested, tuned, versioned and measured like any first-party component.
5. **Reproducibility.** Every SeaBSD image must be rebuildable from this repository alone: sources, build scripts, kernel configuration and overlay. If it cannot be rebuilt, it does not ship.

## Non-goals

- SeaBSD does not try to replace FreeBSD on servers. FreeBSD remains the upstream and the foundation; SeaBSD is a user-facing distribution on top of it.
- We do not ship proprietary drivers in the base image by default. Third-party components are an explicit, informed user choice.
- We do not chase a rolling-release model. Predictable versioned releases with clear upgrade paths matter more to regular users than novelty.
- We do not fork FreeBSD wholesale "just to fork". SeaBSD is an overlay of defaults, tooling and documentation; the base system comes from upstream.

## What success looks like

- A student downloads an ISO, boots a mid-range 2019-era laptop, and gets a working desktop with sound, Wi-Fi and a browser — without opening a terminal once.
- Popular Linux applications run through the linuxolator with the same level of effort as on a mainstream Linux distribution: zero manual setup for the common case.
- A broken sandbox is a non-event: reset it in seconds, keep the user data, move on.
- Every hardware component has a documented status in the compatibility database, contributed by real users of real machines.
