#!/bin/sh
# build-kernel.sh - Build the SeaBSD kernel and install it into a target tree.
#
# Copyright (c) 2026, SeaBSD Project
# SPDX-License-Identifier: BSD-3-Clause
#
# Useful when iterating on the SEABSD kernel configuration without running
# the full ISO pipeline.
#
# Stages (default: build):
#   build    - make buildkernel (KERNCONF=SEABSD)
#   install  - make installkernel into SEABSD_KERNEL_DESTDIR
#
# Environment overrides:
#   SEABSD_FREEBSD_SRC      path to FreeBSD source tree (default: /usr/src)
#   SEABSD_KERNCONF         kernel config name          (default: SEABSD)
#   SEABSD_KERNEL_DESTDIR   install target tree         (default: /var/tmp/seabsd-kernel)
#   SEABSD_KERNEL_NO_MODULES=1  build kernel without modules

set -eu

FREEBSD_SRC="${SEABSD_FREEBSD_SRC:-/usr/src}"
KERNCONF="${SEABSD_KERNCONF:-SEABSD}"
DESTDIR="${SEABSD_KERNEL_DESTDIR:-/var/tmp/seabsd-kernel}"
NPROC="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"

msg() { printf '[seabsd-kernel] %s\n' "$*"; }
die() { printf '[seabsd-kernel] ERROR: %s\n' "$*" >&2; exit 1; }

require_freebsd() {
  [ "$(uname -s)" = "FreeBSD" ] || die "this script must run on FreeBSD (detected: $(uname -s))"
}

build_kernel() {
  msg "buildkernel (KERNCONF=$KERNCONF, parallelism: $NPROC)"
  if [ "${SEABSD_KERNEL_NO_MODULES:-0}" = "1" ]; then
    make -C "$FREEBSD_SRC" buildkernel KERNCONF="$KERNCONF" MODULES_WITH_WORLD="" -DNO_MODULES -j"$NPROC"
  else
    make -C "$FREEBSD_SRC" buildkernel KERNCONF="$KERNCONF" -j"$NPROC"
  fi
}

install_kernel() {
  msg "installkernel into DESTDIR=$DESTDIR"
  make -C "$FREEBSD_SRC" installkernel KERNCONF="$KERNCONF" DESTDIR="$DESTDIR"
  msg "kernel tree ready at $DESTDIR/boot/kernel"
}

case "${1:-build}" in
  build)
    require_freebsd
    build_kernel
    ;;
  install)
    require_freebsd
    install_kernel
    ;;
  all)
    require_freebsd
    build_kernel
    install_kernel
    ;;
  -h|--help|help)
    printf 'Usage: sh build-kernel.sh [build|install|all]\n'
    ;;
  *)
    die "unknown stage: $1 (use build, install or all)"
    ;;
esac
