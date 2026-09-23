#!/bin/sh
# hwcheck.sh - SeaBSD hardware inventory reporter (prototype, v0.1).
#
# Copyright (c) 2026, SeaBSD Project
# SPDX-License-Identifier: BSD-3-Clause
#
# Collects PCI/USB/network/storage/audio inventory so users can attach a
# complete hardware report to GitHub issues. Output is plain text and
# designed to be pasted verbatim. Best run on FreeBSD as root.

set -u

out() { printf '\n== %s ==\n' "$*"; }

out "System"
uname -a
sysctl -n hw.model 2>/dev/null || true
sysctl -n hw.realmem 2>/dev/null || true

out "PCI devices"
if command -v pciconf >/dev/null 2>&1; then
  pciconf -lv
else
  printf 'pciconf not available (non-FreeBSD host?)\n'
fi

out "USB devices"
if command -v usbconfig >/dev/null 2>&1; then
  usbconfig list 2>/dev/null || true
else
  printf 'usbconfig not available\n'
fi

out "Network interfaces"
if command -v ifconfig >/dev/null 2>&1; then
  ifconfig -l
else
  printf 'ifconfig not available\n'
fi

out "Loaded kernel modules"
if command -v kldstat >/dev/null 2>&1; then
  kldstat 2>/dev/null || true
else
  printf 'kldstat not available\n'
fi

out "Audio"
if command -v mixer >/dev/null 2>&1; then
  mixer 2>/dev/null || true
else
  printf 'mixer not available\n'
fi

out "GPU candidates (VGA/display class)"
if command -v pciconf >/dev/null 2>&1; then
  pciconf -lv | grep -iE 'class=0x030|VGA|display' || printf 'no VGA-class devices found\n'
fi

out "TODO(v0.1)"
printf 'Compatibility database lookup will map the PCI/USB IDs above to\n'
printf 'driver names and known status - see docs/hardware-support.md\n'

out "How to report"
printf 'Attach the full output of this script to a GitHub issue:\n'
printf 'https://github.com/mel0k1/SeaBSD/issues\n'
