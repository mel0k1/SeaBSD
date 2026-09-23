# SeaBSD Futex Hardening Plan

## Why futex is the load-bearing wall

Every threaded Linux program synchronises its threads through futexes. glibc's pthreads implementation — mutexes, condition variables, semaphores, barriers, `std::thread`, everything — compiles down to the `futex(2)` syscall family. That means the linuxolator's futex translation path is exercised not occasionally but constantly, by every application we care about: a browser opening a new tab, a game's resource loader, a JVM garbage collector thread, a .NET thread pool worker. When the path is correct, nobody ever notices it; when it is subtly wrong, the failure modes are the worst kinds — intermittent hangs, threads spinning at 100% CPU waiting for a wake-up that never arrives, or deadlocks that appear only under load.

This is why futex bugs are the classic "hard program" killers under the linuxolator. A missing library produces a clean, debuggable error message; a futex timeout that is rounded to the wrong timebase produces a desktop application that freezes once every few hours. SeaBSD's stated goal — making hard programs "just work" — therefore starts with hardening this one syscall family and building the tooling to prove the hardening.

The kernel side is upstream FreeBSD code (`sys/compat/linux/linux_futex.c`); SeaBSD does not fork it. What we can and must do is measure it honestly, diagnose failures precisely, and carry or backport fixes through the process in `kernel-patches/README.md` when upstream has not caught up yet.

## What the probe covers

`tools/probes/futex_stress.c` is a static Linux binary that CI builds on an Ubuntu runner and runs on FreeBSD through the linuxolator (category `futex` in the matrix). Running it on real Linux first validates the probe itself; running it on FreeBSD measures the linuxolator. Each test checks not just the return value but the observable semantics — wake counts, elapsed time windows, and lossless counting under contention.

| Test | futex surface | What breaks on this host if it fails |
| --- | --- | --- |
| `waitwake` | `FUTEX_WAIT`/`FUTEX_WAKE` + `FUTEX_PRIVATE_FLAG` | Every pthread mutex/condvar; the most basic threaded program hangs |
| `timed_rel` | relative timeout on `CLOCK_MONOTONIC`, incl. 1 ms edge | Timed locks return instantly (or never); boot-time timeouts in daemons |
| `timed_abs_mono` | absolute timeout, monotonic timebase | `pthread_cond_timedwait` in monotonic-capable runtimes misfires |
| `timed_abs_rt` | absolute timeout with `FUTEX_CLOCK_REALTIME` | Wall-clock deadlines in Java/.NET/glibc break under clock changes |
| `bitset` | `FUTEX_WAIT_BITSET`/`FUTEX_WAKE_BITSET` matching | Selective wakeups in lock-free and priority structures go wrong |
| `requeue` | `FUTEX_REQUEUE` wake-1 + move-N between futexes | Thundering-herd avoidance collapses; condvar broadcast stalls |
| `waitv` | `futex_waitv` (vectorised wait, newer interface) | Newer glibc/runtime fast paths fail; probe reports SKIP if the kernel lacks it |
| `contention` | 8-thread futex lock, 8000 critical sections | Lost wakeups or lost updates under load — the nastiest class |

The matrix TSV splits these into `futex-core` (all but `waitv`) and `futex-waitv`. A probe may self-report "not implemented on this host" with exit code 77, which the matrix records as `SKIP` — feature detection, not failure.

## How to run it

On CI, the `linux-probes` job builds the probe statically and the `freebsd-linux-matrix` job executes the `futex` category inside the FreeBSD VM. On a FreeBSD workstation or a SeaBSD installation:

```sh
mkdir -p /usr/local/lib/seabsd/probes          # or any directory
cc -O2 -static -o /usr/local/lib/seabsd/probes/futex_stress \
   tools/probes/futex_stress.c -lpthread       # needs a Linux compiler, see docs/futex.md
sh tools/linux-matrix.sh --only futex run      # or run the binary directly
```

Because a Linux compiler is rarely present on FreeBSD, the CI artifact (`linux-probes`) is the intended source of the binary. Diagnostics for a failing or hanging run are collected with `sh tools/futex-diag.sh [-t SECS] [PID]` — thread kernel stacks show a parked `linux_futex_wait` chain directly, and the optional ktrace sample counts actual futex traffic.

## Baseline and risk zones

The v0.1 baseline is FreeBSD 14.1-RELEASE's linuxolator (reported ABI 5.15.0). The core paths the probe covers are implemented upstream and expected to pass; the value of the probe is confirming that continuously on every push, against our pinned userland (glibc 2.39 exercises these paths far more aggressively than CentOS-7-era bases ever did). The zones below are where history says bugs cluster, and where we expect the probe — and its future extensions — to earn its keep:

- **Timeout handling.** Relative vs absolute timeouts, monotonic vs realtime timebases, and rounding to kernel ticks have each produced linuxolator bugs in the past. A timeout rounded down to zero ticks manifests as an instant "successful" return — exactly what `timed_rel`'s 1 ms case is designed to catch.
- **Priority-inheritance futexes** (`FUTEX_LOCK_PI`, `UNLOCK_PI`, `TRYLOCK_PI`, `LOCK_PI2`). Not covered by the probe yet; PI semantics interact with scheduler policy and are the least-travelled path. Covered in the v0.1 audit (see ROADMAP gap list).
- **Robust futex lists** (ownership tracking, `FUTEX_OWNER_DIED` on exit). Used by newer glibc robust mutexes; a race here leaks a stuck lock into an unrelated thread after a crash.
- **`FUTEX_WAKE_OP`** — the atomic-modify-and-wake compound op used by glibc semaphores; untested for now, queued for the audit.
- **`futex_waitv`** — present in newer FreeBSD releases; if the VM reports SKIP, that is a fact to record, not to hide.

## Hard-target watchlist

The programs the user explicitly wants to "chew". Each row maps an application class to the futex surfaces it leans on, so a probe failure immediately tells us which users are affected.

| Target | Threading profile | futex surfaces most exercised | Status (v0.1) |
| --- | --- | --- | --- |
| Steam / games | Loader threads, audio, overlay hooks | wait/wake, requeue, PI (via glibc) | untested (needs base + LSU) |
| Chromium / Electron | Multi-process, heavy condvar use | wait/wake, timed waits, bitsets | untested (needs base + deps) |
| Firefox | Thread pools, IPC | wait/wake, robust mutexes | untested |
| OpenJDK | GC threads, safepoint polling, `LockSupport` | timed waits (both clocks), PI | untested |
| .NET runtime | Thread pool, finalizer | timed waits, waitv fast paths | untested |

"Honest status" applies here as everywhere in SeaBSD: until the matrix records a PASS for these with the probe and with the real application, they stay untested — the watchlist exists to make that visible and to prioritise the audit.

## Strategy: measure, diagnose, fix upstream

1. **Measure continuously.** The probe runs on every push on a FreeBSD runner; results land in the matrix report. A green `futex` category is a release gate for v0.1's "hard programs" promise.
2. **Diagnose precisely.** When a failure or hang appears, `tools/futex-diag.sh` collects ABI levels, kernel stacks and ktrace samples in a form that maps directly onto `sys/compat/linux/linux_futex.c` source lines.
3. **Fix upstream-first.** Kernel-level gaps are filed against upstream FreeBSD with the failing probe attached (the probe is a ready-made regression test for the upstream report). Distribution-level workarounds live in our overlay. Carried patches follow `kernel-patches/README.md`: versioned, justified, each with a probe that fails without it.
4. **Extend the watchlist tests.** The v0.1 audit adds PI, robust-list and `WAKE_OP` probes so the risk zones above become measured zones.

## Success criteria

- v0.1: `futex-core` PASS on every supported FreeBSD runner, `futex-waitv` PASS or documented-SKIP; any FAIL traced to an upstream report or a carried patch.
- v0.2: the PI, robust-list and `WAKE_OP` surfaces have probes and recorded results; every entry in the hard-target watchlist has at least an application-launch probe in the matrix.
- Ongoing: no futex regression reaches a release without being caught by the matrix first.
