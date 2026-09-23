#!/bin/sh
# linux-matrix.sh - SeaBSD linuxolator application compatibility matrix runner.
#
# Copyright (c) 2026, SeaBSD Project
# SPDX-License-Identifier: BSD-3-Clause
#
# Runs the compatibility matrix defined in tools/linux-matrix.tsv on a FreeBSD
# host: executes each application probe through the linuxolator, classifies
# the result and writes a machine-readable YAML report plus a human summary.
#
# Stages:
#   check  - verify the linuxolator environment (module, base, mounts)
#   list   - print the matrix contents
#   run    - execute the matrix and write the report (default)
#
# Options (must come before the stage):
#   --only CATEGORY   run entries of one category only (exact match)
#   --timeout SECS    per-probe timeout (default: 15)
#   --strict          treat MISSING entries as failures for the exit code
#   --report PATH     report output path (default: dist/linux-matrix-report.yaml)
#
# Environment overrides:
#   SEABSD_MATRIX_TSV      matrix data file (default: tools/linux-matrix.tsv)
#   SEABSD_MATRIX_REPORT   report path (default: dist/linux-matrix-report.yaml)
#   SEABSD_MATRIX_TIMEOUT  default probe timeout in seconds (default: 15)
#   SEABSD_PROBES_DIR      probe directory substituted for "@PROBES@"
#                          (default: /usr/local/lib/seabsd/probes)
#
# Per-entry statuses:
#   PASS     probe ran and output matched the expected pattern
#   FAIL     probe ran but output did not match, or the probe errored
#   TIMEOUT  probe exceeded the time limit (killed)
#   SKIP     optional entry whose binary is not installed, or a probe that
#            self-reported "not implemented on this host" (exit code 77)
#   MISSING  required entry whose binary is not installed
#
# Probe binaries: a binary column of "@PROBES@/NAME" is expanded to
# $SEABSD_PROBES_DIR/NAME (default: /usr/local/lib/seabsd/probes). That
# directory holds static Linux probe binaries built by the CI linux-probes
# job from tools/probes/*.c (see docs/futex.md).
#
# Exit codes: 0 ok, 1 matrix had FAIL/TIMEOUT (or MISSING with --strict),
# 2 environment check failed (not FreeBSD), 3 usage error.

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TSV="${SEABSD_MATRIX_TSV:-$SCRIPT_DIR/linux-matrix.tsv}"
REPORT="${SEABSD_MATRIX_REPORT:-dist/linux-matrix-report.yaml}"
TIMEOUT_SECS="${SEABSD_MATRIX_TIMEOUT:-15}"
ONLY=""
STRICT=0

log() { printf '[linux-matrix] %s\n' "$*"; }
err() { printf '[linux-matrix] ERROR: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
Usage: sh tools/linux-matrix.sh [options] [stage]

Stages:
  check   verify the linuxolator environment
  list    print the matrix contents
  run     execute the matrix and write the report (default)

Options:
  --only CATEGORY   run entries of one category only
  --timeout SECS    per-probe timeout (default: 15)
  --strict          count MISSING entries as failures
  --report PATH     report output path
  -h, --help        show this help

Matrix data file: tools/linux-matrix.tsv (fields documented in its header).
USAGE
}

have_timeout() {
  command -v timeout >/dev/null 2>&1
}

check_env() {
  if [ "$(uname -s)" != "FreeBSD" ]; then
    err "linux-matrix must run on FreeBSD (detected: $(uname -s))"
    exit 2
  fi

  printf '== SeaBSD linuxolator environment check ==\n'
  printf 'host: %s\n' "$(uname -sr)"

  # The presence of the compat.linux.osrelease sysctl is the reliable signal
  # that the linuxolator is loaded; kldstat -m does not match reliably here.
  osrelease=$(sysctl -n compat.linux.osrelease 2>/dev/null || printf '')
  if [ -n "$osrelease" ]; then
    printf 'module linux64: loaded (compat.linux.osrelease: %s)\n' "$osrelease"
  else
    printf 'module linux64: NOT loaded (hint: sysrc linux_enable=YES && service linux start)\n'
  fi

  if kldstat -m linux >/dev/null 2>&1; then
    printf 'module linux (32-bit): loaded\n'
  else
    printf 'module linux (32-bit): not loaded (optional)\n'
  fi

  if [ -d /compat/linux ]; then
    printf '/compat/linux: present\n'
  else
    printf '/compat/linux: MISSING (install a Linux base package, see docs/linuxolator.md)\n'
  fi

  if mount 2>/dev/null | grep -q linprocfs; then
    printf 'linprocfs: mounted\n'
  else
    printf 'linprocfs: not mounted (hint: service linux restart)\n'
  fi

  if have_timeout; then
    printf 'timeout(1): available\n'
  else
    printf 'timeout(1): NOT available - probes will run without a time limit\n'
  fi
}

list_matrix() {
  log "matrix file: $TSV"
  printf '%-16s %-12s %-9s %s\n' 'NAME' 'CATEGORY' 'OPTIONAL' 'BINARY'
  # "|| [ -n ... ]" keeps a final line without a trailing newline visible.
  while IFS='|' read -r name category optional binary args expect \
      || [ -n "${name:-}" ]; do
    case "$name" in
      ''|'#'*) continue ;;
    esac
    printf '%-16s %-12s %-9s %s\n' "$name" "$category" "$optional" "$binary"
  done < "$TSV"
}

run_matrix() {
  if [ ! -f "$TSV" ]; then
    err "matrix file not found: $TSV"
    exit 3
  fi

  mkdir -p "$(dirname -- "$REPORT")"
  REPORT_TMP=$(mktemp /var/tmp/linux-matrix-report.XXXXXX) || exit 1
  OUT_TMP=$(mktemp /var/tmp/linux-matrix-out.XXXXXX) || exit 1
  trap 'rm -f "$REPORT_TMP" "$OUT_TMP"' EXIT HUP INT TERM

  c_pass=0; c_fail=0; c_time=0; c_skip=0; c_miss=0

  {
    printf '# SeaBSD linuxolator compatibility matrix report\n'
    printf 'generated: "%s"\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'host: "%s"\n' "$(uname -sr)"
    printf 'linux_osrelease: "%s"\n' "$(sysctl -n compat.linux.osrelease 2>/dev/null || printf 'unknown')"
    printf 'timeout_secs: %s\n' "$TIMEOUT_SECS"
    printf 'strict: %s\n' "$STRICT"
    printf 'results:\n'
  } > "$REPORT_TMP"

  if ! have_timeout; then
    log "WARNING: timeout(1) not available, probes run without a time limit"
  fi

  # "|| [ -n ... ]" keeps a final line without a trailing newline visible.
  while IFS='|' read -r name category optional binary args expect \
      || [ -n "${name:-}" ]; do
    case "$name" in
      ''|'#'*) continue ;;
    esac

    if [ -z "$name" ] || [ -z "$category" ] || [ -z "$binary" ] || [ -z "$expect" ]; then
      log "WARNING: skipping malformed matrix line: $name"
      continue
    fi

    if [ -n "$ONLY" ] && [ "$category" != "$ONLY" ]; then
      continue
    fi

    # Probe binaries built by CI live in a configurable directory.
    case "$binary" in
      @PROBES@/*)
        binary="${SEABSD_PROBES_DIR:-/usr/local/lib/seabsd/probes}${binary#@PROBES@}"
        ;;
    esac

    case "$optional" in
      yes) opt_flag=1 ;;
      *)   opt_flag=0 ;;
    esac

    if [ -n "${binary%%/*}" ]; then
      bpath=$(command -v -- "$binary" 2>/dev/null || printf '')
    else
      if [ -x "$binary" ]; then bpath=$binary; else bpath=''; fi
    fi

    if [ -z "$bpath" ]; then
      if [ "$opt_flag" -eq 1 ]; then
        c_skip=$((c_skip + 1))
        status='SKIP'; detail='binary not installed (optional entry)'
        printf '[SKIP]    %s (%s): %s\n' "$name" "$category" "$detail"
      else
        c_miss=$((c_miss + 1))
        status='MISSING'; detail='required binary not installed'
        printf '[MISSING] %s (%s): %s\n' "$name" "$category" "$detail"
      fi
      printf '  - name: "%s"\n    category: "%s"\n    status: %s\n    detail: "%s"\n' \
        "$name" "$category" "$status" "$detail" >> "$REPORT_TMP"
      continue
    fi

    : > "$OUT_TMP"
    rc=0
    if have_timeout; then
      # shellcheck disable=SC2086
      timeout "$TIMEOUT_SECS" "$bpath" $args > "$OUT_TMP" 2>&1 || rc=$?
    else
      # shellcheck disable=SC2086
      "$bpath" $args > "$OUT_TMP" 2>&1 || rc=$?
    fi

    case "$rc" in
      124)
        c_time=$((c_time + 1))
        printf '[TIMEOUT] %s (%s): exceeded %ss\n' "$name" "$category" "$TIMEOUT_SECS"
        printf '  - name: "%s"\n    category: "%s"\n    status: TIMEOUT\n    exit: %s\n    detail: "exceeded %ss limit"\n' \
          "$name" "$category" "$rc" "$TIMEOUT_SECS" >> "$REPORT_TMP"
        continue
        ;;
      77)
        # Probe self-reported "not implemented on this host": this is
        # feature detection, not a failure. See tools/probes/.
        c_skip=$((c_skip + 1))
        printf '[SKIP]    %s (%s): probe self-reported not implemented\n' "$name" "$category"
        printf '  - name: "%s"\n    category: "%s"\n    status: SKIP\n    exit: 77\n    detail: "probe self-reported not implemented on this host"\n' \
          "$name" "$category" >> "$REPORT_TMP"
        ;;
      0)
        if grep -Eq -- "$expect" "$OUT_TMP"; then
          c_pass=$((c_pass + 1))
          printf '[PASS]    %s (%s)\n' "$name" "$category"
          printf '  - name: "%s"\n    category: "%s"\n    status: PASS\n    exit: 0\n' \
            "$name" "$category" >> "$REPORT_TMP"
        else
          c_fail=$((c_fail + 1))
          printf '[FAIL]    %s (%s): output did not match expected pattern\n' "$name" "$category"
          detail=$(tail -n 3 "$OUT_TMP" | tr '\n' ' ' | tr -s ' ' | cut -c1-200)
          printf '  - name: "%s"\n    category: "%s"\n    status: FAIL\n    exit: 0\n    detail: "output mismatch: %s"\n' \
            "$name" "$category" "$detail" >> "$REPORT_TMP"
        fi
        ;;
      *)
        c_fail=$((c_fail + 1))
        printf '[FAIL]    %s (%s): probe exited with code %s\n' "$name" "$category" "$rc"
        detail=$(tail -n 3 "$OUT_TMP" | tr '\n' ' ' | tr -s ' ' | cut -c1-200)
        printf '  - name: "%s"\n    category: "%s"\n    status: FAIL\n    exit: %s\n    detail: "probe error: %s"\n' \
          "$name" "$category" "$rc" "$detail" >> "$REPORT_TMP"
        ;;
    esac
  done < "$TSV"

  {
    printf 'summary:\n'
    printf '  pass: %s\n' "$c_pass"
    printf '  fail: %s\n' "$c_fail"
    printf '  timeout: %s\n' "$c_time"
    printf '  skip: %s\n' "$c_skip"
    printf '  missing: %s\n' "$c_miss"
  } >> "$REPORT_TMP"

  mv -f "$REPORT_TMP" "$REPORT"
  trap - EXIT HUP INT TERM
  rm -f "$OUT_TMP"

  printf '\n== Summary ==\n'
  printf 'PASS: %s  FAIL: %s  TIMEOUT: %s  SKIP: %s  MISSING: %s\n' \
    "$c_pass" "$c_fail" "$c_time" "$c_skip" "$c_miss"
  log "report written to $REPORT"

  if [ "$c_fail" -gt 0 ] || [ "$c_time" -gt 0 ]; then
    exit 1
  fi
  if [ "$STRICT" -eq 1 ] && [ "$c_miss" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

# --- Argument parsing -------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --only)    [ $# -ge 2 ] || { err "--only needs a value"; exit 3; }; ONLY=$2; shift 2 ;;
    --timeout) [ $# -ge 2 ] || { err "--timeout needs a value"; exit 3; }; TIMEOUT_SECS=$2; shift 2 ;;
    --report)  [ $# -ge 2 ] || { err "--report needs a value"; exit 3; }; REPORT=$2; shift 2 ;;
    --strict)  STRICT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --)        shift; break ;;
    -*)        err "unknown option: $1"; usage; exit 3 ;;
    *)         break ;;
  esac
done

if [ $# -gt 1 ]; then
  err "unexpected extra arguments: $*"
  usage
  exit 3
fi

case "${1:-run}" in
  check) check_env ;;
  list)  list_matrix ;;
  run)   run_matrix ;;
  *)     err "unknown stage: $1"; usage; exit 3 ;;
esac
