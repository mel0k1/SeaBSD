#!/bin/sh
# fetch-linux-base.sh - Download and unpack the pinned SeaBSD Linux base.
#
# Copyright (c) 2026, SeaBSD Project
# SPDX-License-Identifier: BSD-3-Clause
#
# Installs the frozen v0.1 Linux base (see docs/linux-base.md) under
# /compat/linux: download the pinned Ubuntu base rootfs, verify its SHA256,
# and unpack it. The script is idempotent and refuses to overwrite an
# existing base unless --force is given.
#
# Options:
#   --dest DIR   target directory (default: /compat/linux, env SEABSD_COMPAT_DIR)
#   --force      replace an existing base
#   -h, --help   show this help
#
# Environment overrides:
#   SEABSD_COMPAT_DIR      target directory          (default: /compat/linux)
#   SEABSD_LINUX_BASE_URL  pinned rootfs URL         (default: see docs/linux-base.md)
#   SEABSD_LINUX_BASE_SHA  pinned SHA256             (default: see docs/linux-base.md)
#   SEABSD_BASE_WORKDIR    download/cache directory  (default: /var/tmp/seabsd-linux-base)

set -eu

# Pinned v0.1 base — docs/linux-base.md is the source of truth for these values.
BASE_URL="${SEABSD_LINUX_BASE_URL:-https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.5-base-amd64.tar.gz}"
BASE_SHA256="${SEABSD_LINUX_BASE_SHA:-e77b6f10c2590cef872b33ee9f635a0e3fd1f57fb074c0e52b5c7f56147a0c86}"
COMPAT_DIR="${SEABSD_COMPAT_DIR:-/compat/linux}"
WORK_DIR="${SEABSD_BASE_WORKDIR:-/var/tmp/seabsd-linux-base}"
FORCE=0

msg() { printf '[linux-base] %s\n' "$*"; }
err() { printf '[linux-base] ERROR: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
Usage: sh tools/fetch-linux-base.sh [--dest DIR] [--force]

Download the pinned SeaBSD Linux base rootfs, verify its SHA256 and unpack
it into the target directory. Idempotent: refuses to overwrite an existing
base unless --force is used. Pinned values come from docs/linux-base.md.

After installation:
  sysrc linux_enable=YES && service linux start
  sh tools/linux-matrix.sh --only base run
USAGE
}

fetch_file() {
  _url=$1
  _out=$2
  if command -v fetch >/dev/null 2>&1; then
    fetch -o "$_out" "$_url"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$_out" "$_url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$_out" "$_url"
  else
    err "no download tool found (need fetch, curl or wget)"
    return 1
  fi
}

sha256_of() {
  if command -v sha256 >/dev/null 2>&1; then
    sha256 -q "$1"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    err "no sha256 tool found (need sha256 or sha256sum)"
    return 1
  fi
}

# --- Argument parsing -------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --dest)    [ $# -ge 2 ] || { err "--dest needs a value"; exit 3; }; COMPAT_DIR=$2; shift 2 ;;
    --force)   FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --)        shift; break ;;
    -*)        err "unknown option: $1"; usage; exit 3 ;;
    *)         err "unexpected argument: $1"; usage; exit 3 ;;
  esac
done

# --- Preflight --------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
  case "$COMPAT_DIR" in
    /compat|/compat/*)
      err "installing into $COMPAT_DIR requires root; use --dest DIR to unpack elsewhere"
      exit 1
      ;;
  esac
fi

marker="$COMPAT_DIR/.seabsd-base"
if [ -f "$marker" ] && [ "$FORCE" -ne 1 ]; then
  msg "base already installed at $COMPAT_DIR (use --force to replace)"
  exit 0
fi

mkdir -p "$WORK_DIR"
tarball="$WORK_DIR/$(basename -- "$BASE_URL")"

# --- Download and verify ----------------------------------------------------

if [ -f "$tarball" ]; then
  actual=$(sha256_of "$tarball")
  if [ "$actual" != "$BASE_SHA256" ]; then
    msg "cached file hash mismatch, re-downloading"
    rm -f "$tarball"
  fi
fi

if [ ! -f "$tarball" ]; then
  msg "downloading pinned base ($(basename -- "$BASE_URL"))"
  fetch_file "$BASE_URL" "$tarball"
fi

actual=$(sha256_of "$tarball")
if [ "$actual" != "$BASE_SHA256" ]; then
  err "SHA256 mismatch"
  err "  expected: $BASE_SHA256"
  err "  actual:   $actual"
  exit 1
fi
msg "SHA256 verified: $actual"

# --- Unpack -----------------------------------------------------------------

if [ "$FORCE" -eq 1 ] && [ -d "$COMPAT_DIR" ] && [ -n "$(ls -A "$COMPAT_DIR" 2>/dev/null)" ]; then
  msg "removing previous base at $COMPAT_DIR"
  rm -rf "$COMPAT_DIR"
fi
mkdir -p "$COMPAT_DIR"

msg "unpacking into $COMPAT_DIR"
tar -xzf "$tarball" -C "$COMPAT_DIR"

if [ ! -x "$COMPAT_DIR/usr/bin/ls" ]; then
  err "unpack succeeded but $COMPAT_DIR/usr/bin/ls is missing - base is not usable"
  exit 1
fi

{
  printf 'name=SeaBSD pinned Linux base\n'
  printf 'url=%s\n' "$BASE_URL"
  printf 'sha256=%s\n' "$BASE_SHA256"
  printf 'installed=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  printf 'decision=docs/linux-base.md\n'
} > "$marker"

msg "base installed: $COMPAT_DIR"
msg "next: sysrc linux_enable=YES && service linux start"
msg "then: sh tools/linux-matrix.sh --only base run"
