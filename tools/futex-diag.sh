#!/bin/sh
# futex-diag.sh - Collect linuxolator futex diagnostics for bug reports.
#
# Copyright (c) 2026, SeaBSD Project
# SPDX-License-Identifier: BSD-3-Clause
#
# Gathers, in one shot, everything a developer needs to analyse a futex
# problem under the linuxolator: kernel and Linux ABI levels, loaded linux
# modules, compat mounts, and - for a given PID - per-thread kernel stacks
# (which show the exact futex sleep chain) plus an optional ktrace syscall
# sample counting futex traffic.
#
# Usage:
#   sh tools/futex-diag.sh                  host-level diagnostics only
#   sh tools/futex-diag.sh PID              + thread stacks and fds of PID
#   sh tools/futex-diag.sh -t SECS PID      + ktrace syscall sample
#
# Exit codes: 0 ok, 2 not FreeBSD, 3 usage error.

set -u

TRACE_SECS=0
PID=""

err() { printf '[futex-diag] ERROR: %s\n' "$*" >&2; }
out() { printf '\n== %s ==\n' "$*"; }

usage() {
  cat <<'USAGE'
Usage: sh tools/futex-diag.sh [-t SECS] [PID]

Collect linuxolator futex diagnostics. Without a PID, host-level data is
printed. With a PID (e.g. a stuck Linux process), per-thread kernel stacks
and an fd snapshot are added. With -t SECS, a ktrace syscall sample of the
PID is taken and the futex traffic is summarised.

Attach the full output to your GitHub issue together with the matrix report
(dist/linux-matrix-report.yaml).
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -t) [ $# -ge 2 ] || { err "-t needs a value"; exit 3; }; TRACE_SECS=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) err "unknown option: $1"; usage; exit 3 ;;
    *)  if [ -z "$PID" ]; then PID=$1; else err "unexpected argument: $1"; usage; exit 3; fi; shift ;;
  esac
done

if [ "$(uname -s)" != "FreeBSD" ]; then
  err "this tool collects FreeBSD diagnostics (detected: $(uname -s))"
  exit 2
fi

if [ -n "$PID" ] && ! kill -0 "$PID" 2>/dev/null; then
  err "process $PID does not exist (or is not ours to inspect)"
  exit 3
fi

printf '# SeaBSD futex diagnostics\n'
printf 'collected: "%s"\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"

out "Host"
uname -sr
sysctl -n kern.osreldate 2>/dev/null || true

out "Linuxolator ABI"
osrel=$(sysctl -n compat.linux.osrelease 2>/dev/null || printf '')
if [ -n "$osrel" ]; then
  printf 'compat.linux.osrelease: %s\n' "$osrel"
else
  printf 'compat.linux.osrelease: NOT PRESENT - the linuxolator is not loaded\n'
  printf '(futex diagnostics below are meaningless without it)\n'
fi
sysctl compat.linux 2>/dev/null || true

out "Linux modules"
kldstat 2>/dev/null | grep -iE 'linux|linproc|linsys' || printf 'no linux modules loaded\n'

out "Compat mounts"
mount 2>/dev/null | grep -E '/compat|linprocfs|linsysfs' || printf 'no compat mounts\n'

if [ -n "$PID" ]; then
  out "Process $PID overview"
  if command -v procstat >/dev/null 2>&1; then
    procstat binary "$PID" 2>/dev/null || true
    procstat -t "$PID" 2>/dev/null || true
  else
    printf 'procstat not available\n'
  fi

  # Kernel stacks are the core of the report: a thread parked in
  # linux_futex_wait / sleepq / cv_wait shows exactly where it is stuck.
  out "Thread kernel stacks (procstat -kk)"
  if command -v procstat >/dev/null 2>&1; then
    procstat -kk "$PID" 2>/dev/null | head -120 || true
  else
    printf 'procstat not available\n'
  fi

  out "File descriptors (first 40)"
  if command -v procstat >/dev/null 2>&1; then
    procstat -f "$PID" 2>/dev/null | head -40 || true
  else
    printf 'procstat not available\n'
  fi
fi

if [ -n "$PID" ] && [ "$TRACE_SECS" -gt 0 ]; then
  if command -v ktrace >/dev/null 2>&1 && command -v kdump >/dev/null 2>&1; then
    TF=$(mktemp /var/tmp/futex-diag-ktrace.XXXXXX) || exit 1
    out "ktrace syscall sample (${TRACE_SECS}s)"
    printf 'sampling PID %s ...\n' "$PID"
    ktrace -f "$TF" -p "$PID" 2>/dev/null || true
    sleep "$TRACE_SECS"
    ktrace -c -p "$PID" 2>/dev/null || true
    if [ -s "$TF" ]; then
      total=$(kdump -f "$TF" 2>/dev/null | grep -c 'CALL' || true)
      ftx=$(kdump -f "$TF" 2>/dev/null | grep -ci 'futex' || true)
      printf 'syscalls in sample: %s, futex-related: %s\n' "$total" "$ftx"
      printf 'first futex calls:\n'
      kdump -f "$TF" 2>/dev/null | grep -i 'futex' | head -20 || true
    else
      printf 'ktrace produced no data (need root? tracing enabled?)\n'
    fi
    rm -f "$TF"
  else
    printf 'ktrace/kdump not available\n'
  fi
fi

out "How to report"
printf 'Attach this output plus the matrix report to:\n'
printf 'https://github.com/mel0k1/SeaBSD/issues\n'
printf 'Context for developers: docs/futex.md\n'
