# SeaBSD Kernel Patches

This directory holds kernel patches that SeaBSD carries on top of the upstream FreeBSD source tree, together with the policy that governs them.

## Policy: upstream-first

SeaBSD does not maintain a hidden kernel fork. A patch may live here only if all of the following are true:

1. **Upstream is engaged.** The patch has been submitted (or is about to be submitted with our knowledge of the outcome) to FreeBSD — `review.FreeBSD.org` differential or the freebsd-emulation/hackers lists for `sys/compat/linux/` issues. The submission link is recorded in the patch header.
2. **A probe exists.** Every carried patch must have a regression probe in the compatibility matrix (`tools/probes/`, exercised via `tools/linux-matrix.sh`) that fails without the patch and passes with it. A patch without a failing probe is a patch without evidence — it does not get carried.
3. **The base commit is pinned.** Patches are developed against a specific `releng/` branch (v0.1: `releng/14.1`). `PROVENANCE` records the exact base commit hash, so a rebuild is reproducible and a rebase is an explicit, reviewed act.
4. **The expiry is honest.** Carried patches are a debt, not a feature. Each entry in `PROVENANCE` lists the upstream state (`submitted` / `accepted` / `rejected` / `stalled`). A patch that is `stalled` for more than one SeaBSD minor release must be re-evaluated: rebase, escalate upstream, or drop the patch and the promise it made.

## Layout

```
kernel-patches/
  README.md                  this file
  <topic>/                   one directory per area, e.g. futex/
    NNNN-short-summary.patch  mbox/format-patch files, numbered in apply order
    series                   list of patch files in the exact apply order
    PROVENANCE               per-patch: base commit, upstream link, status,
                               failing probe name, reason for carrying
```

Generate patches with `git format-patch` so they apply cleanly with `git am`; keep each patch single-purpose and self-contained (builds and boots alone).

## Applying

Patches are applied during the kernel build stage, after the FreeBSD source is fetched. `build/build-kernel.sh` will grow an explicit, logged `git am` step over `kernel-patches/*/series` (see ROADMAP, infrastructure); until then, application is a manual, documented build step.

## Current status

No patches are currently carried. The futex track (see `docs/futex.md`) runs its probes against stock `releng/14.1` code; if the matrix surfaces a kernel-level gap, the first entries here will be `kernel-patches/futex/`.
