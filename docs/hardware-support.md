# SeaBSD Hardware Support Plan

## Goal

A desktop operating system lives or dies by the first ten minutes on real hardware. SeaBSD aims to make those ten minutes boring: detect everything, tell the user the truth about what works, and configure as much as possible automatically. This document describes how we get there and how the compatibility database is built.

## Approach

SeaBSD follows a four-step loop for every hardware component:

1. **Detect.** Enumerate PCI and USB identifiers (`pciconf -lv`, `usbconfig`) on boot and via the `hwcheck` tool.
2. **Map.** Look the identifiers up in the compatibility database: which driver claims the device, and what is its known status.
3. **Report.** Present the result to the user in plain language — before and after installation. Silence is not an option: "no driver found for this Wi-Fi adapter" is better than a boot into a desktop with dead Wi-Fi.
4. **Fix.** Where a missing driver or a bug is the root cause, work upstream-first: linuxkpi plumbing, driver patches, or documented workarounds in the database entry.

## The hwcheck tool

`tools/hwcheck.sh` is the first implementation of detection and reporting. On a FreeBSD system it collects:

- system identity: kernel version, CPU model, memory;
- PCI device tree with vendor/device IDs (the core of a hardware report);
- USB device list;
- network interface names;
- loaded kernel modules;
- audio mixer presence.

The output is designed to be attached to a GitHub issue verbatim. Later versions will compare the report against the compatibility database and print a per-device status table instead of raw inventory.

## Compatibility database format

Entries are small YAML files under a `compat/` directory (to be introduced in v0.1), one per device:

```yaml
- vendor_id: "0x8086"
  device_id: "0x2723"
  name: "Intel AX200 Wi-Fi"
  driver: "iwlwifi (linuxkpi)"
  status: works
  notes: "Firmware loads on 14.x; WPA3 verified."
  reports: 3
```

Rules for the database:

- Every entry must be backed by at least one real hardware report from `hwcheck` output.
- `status` uses fixed values: `works`, `partial`, `broken`, `unknown`.
- `notes` state reality, including kernel version if behaviour changed across releases.

## Preliminary support matrix (to be verified and expanded)

| Component class | Path on FreeBSD | Notes |
| --- | --- | --- |
| Wi-Fi (Intel) | `iwlwifi` via linuxkpi | Primary focus for laptops; firmware packaging matters |
| Wi-Fi (Realtek) | `rtw88`/`rtw89` via linuxkpi | Coverage growing upstream; needs testing on common USB/M.2 cards |
| Ethernet | `em`, `igc`, `re`, `alc`, `axe` | Generally solid; mostly a reporting task |
| GPU (Intel) | `i915kms` via linuxkpi | Video output usually fine; verify suspend/resume and external displays |
| GPU (AMD) | `amdgpu` via linuxkpi | Newer APUs need recent upstream; verify HDMI audio |
| GPU (NVIDIA) | Proprietary driver via ports | Explicit user opt-in; not in the base image |
| Audio | `hdaa`/`snd_hda`, OSS | Works broadly; linuxolator ALSA bridge is a separate linuxolator-track task |
| Bluetooth | `ng_ubt` and related | Pairing stack present; per-device verification needed |
| Webcams | `webcamd` + `cuse` | UVC-class devices mostly covered; USB ID database needed |

## Known limitations to be honest about

- Some laptop Wi-Fi chipsets have no driver at all yet; the database must say so clearly.
- Suspend/resume is heavily laptop-dependent and must be part of every hardware report, not an afterthought.
- GPU firmware packaging has license implications that vary by component; the installer will make third-party firmware an explicit choice.

## How to contribute data

Run `sh tools/hwcheck.sh` on a FreeBSD (or SeaBSD) system, attach the output to a GitHub issue, and describe what works. Reports from laptops are especially valuable: laptop-class hardware is exactly where "BSD for users" has historically been weakest.
