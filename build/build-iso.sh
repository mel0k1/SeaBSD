#!/bin/sh
# build-iso.sh - Build a SeaBSD installation ISO from FreeBSD sources.
#
# Copyright (c) 2026, SeaBSD Project
# SPDX-License-Identifier: BSD-3-Clause
#
# Requirements: FreeBSD 14.x host (or VM), ~40 GB free disk space, git.
#
# Stages (default: all):
#   fetch   - clone or update the FreeBSD source tree
#   world   - make buildworld
#   kernel  - make buildkernel (KERNCONF=SEABSD)
#   iso     - assemble the release ISO
#
# Environment overrides:
#   SEABSD_FREEBSD_SRC    path to FreeBSD source tree  (default: /usr/src)
#   SEABSD_FREEBSD_BRANCH FreeBSD branch/tag           (default: release/14.3.0)
#   SEABSD_KERNCONF       kernel config name           (default: SEABSD)
#   SEABSD_VERSION        SeaBSD version string        (default: 0.0.1-snapshot)
#   SEABSD_CHROOTDIR      release working directory    (default: /var/tmp/seabsd-build)
#   SEABSD_SKIP_FETCH     set to 1 to skip stage "fetch"

set -eu

FREEBSD_SRC="${SEABSD_FREEBSD_SRC:-/usr/src}"
FREEBSD_BRANCH="${SEABSD_FREEBSD_BRANCH:-release/14.3.0}"
KERNCONF="${SEABSD_KERNCONF:-SEABSD}"
VERSION="${SEABSD_VERSION:-0.0.1-snapshot}"
CHROOTDIR="${SEABSD_CHROOTDIR:-/var/tmp/seabsd-build}"
FREEBSD_REPO="https://git.FreeBSD.org/src.git"
NPROC="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"

msg() { printf '[seabsd-build] %s\n' "$*"; }
die() { printf '[seabsd-build] ERROR: %s\n' "$*" >&2; exit 1; }

require_freebsd() {
  [ "$(uname -s)" = "FreeBSD" ] || die "this script must run on FreeBSD (detected: $(uname -s))"
}

fetch_src() {
  if [ -d "$FREEBSD_SRC/.git" ]; then
    msg "updating FreeBSD sources in $FREEBSD_SRC (branch: $FREEBSD_BRANCH)"
    git -C "$FREEBSD_SRC" fetch --all --tags
    git -C "$FREEBSD_SRC" checkout "$FREEBSD_BRANCH"
  else
    msg "cloning FreeBSD sources ($FREEBSD_BRANCH) into $FREEBSD_SRC"
    git clone --depth 1 --branch "$FREEBSD_BRANCH" "$FREEBSD_REPO" "$FREEBSD_SRC"
  fi
}

build_world() {
  msg "buildworld (parallelism: $NPROC)"
  make -C "$FREEBSD_SRC" buildworld -j"$NPROC"
}

build_kernel() {
  msg "buildkernel (KERNCONF=$KERNCONF)"
  make -C "$FREEBSD_SRC" buildkernel KERNCONF="$KERNCONF" -j"$NPROC"
}

build_iso() {
  msg "assembling release (SeaBSD $VERSION)"
  # TODO(seabsd-v0.1): apply build/overlay to the release tree before ISO
  # assembly, and pin the ports tree used by release tooling.
  make -C "$FREEBSD_SRC/release" \
    KERNCONF="$KERNCONF" \
    BUILDNAME="SeaBSD-$VERSION" \
    CHROOTDIR="$CHROOTDIR" \
    WITHOUT_VMIMAGES=1 \
    WITH_COMPRESSED_IMAGES=none \
    NO_CLEAN=0 \
    release
  make -C "$FREEBSD_SRC/release" cdrom
  msg "done - look for disc1.iso under $CHROOTDIR"
}

usage() {
  cat <<'USAGE'
Usage: sh build-iso.sh [stage]

Stages:
  fetch    clone or update the FreeBSD source tree
  world    make buildworld
  kernel   make buildkernel (KERNCONF=SEABSD)
  iso      assemble the release ISO
  all      run fetch, world, kernel, iso (default)

Environment variables are documented in the script header and build/README.md.
USAGE
}

case "${1:-all}" in
  fetch)
    require_freebsd
    fetch_src
    ;;
  world)
    require_freebsd
    build_world
    ;;
  kernel)
    require_freebsd
    build_kernel
    ;;
  iso)
    require_freebsd
    build_iso
    ;;
  all)
    require_freebsd
    [ "${SEABSD_SKIP_FETCH:-0}" = "1" ] || fetch_src
    build_world
    build_kernel
    build_iso
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    die "unknown stage: $1"
    ;;
esac
