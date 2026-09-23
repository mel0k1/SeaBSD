#!/bin/sh
# structure-check.sh - Validate repository structure and scan for secrets.
#
# Copyright (c) 2026, SeaBSD Project
# SPDX-License-Identifier: BSD-3-Clause
#
# Runs in CI on every push and pull request. POSIX sh, no dependencies.

set -eu

fail=0

check_file() {
  if [ ! -f "$1" ]; then
    printf 'MISSING: %s\n' "$1"
    fail=1
  fi
}

check_executable_bit() {
  if [ -f "$1" ] && [ ! -x "$1" ]; then
    printf 'NOT EXECUTABLE: %s (run: chmod +x %s)\n' "$1" "$1"
    fail=1
  fi
}

# --- Required files ---------------------------------------------------------

for f in \
  README.md \
  README.ru.md \
  LICENSE \
  VISION.md \
  ROADMAP.md \
  CONTRIBUTING.md \
  build/README.md \
  build/build-iso.sh \
  build/build-kernel.sh \
  build/kernel/SEABSD \
  build/overlay/README.md \
  docs/linuxolator.md \
  docs/hardware-support.md \
  tools/hwcheck.sh \
  tools/linux-matrix.sh \
  tools/linux-matrix.tsv \
  .github/workflows/ci.yml
do
  check_file "$f"
done

for f in build/build-iso.sh build/build-kernel.sh tools/structure-check.sh tools/hwcheck.sh tools/linux-matrix.sh; do
  check_executable_bit "$f"
done

# --- Secret scan ------------------------------------------------------------

# NOTE: character classes in the pattern are intentionally written so that this
# script does not match itself during the recursive scan.
pattern='(github[_]pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{30,})'

if grep -RInE "$pattern" --exclude-dir=.git . 2>/dev/null; then
  printf 'ERROR: potential GitHub token found in tracked files (see matches above)\n'
  fail=1
fi

# --- Verdict ----------------------------------------------------------------

if [ "$fail" -eq 0 ]; then
  printf 'structure-check: OK\n'
else
  printf 'structure-check: FAILED\n'
  exit 1
fi
