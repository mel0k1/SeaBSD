# SeaBSD Filesystem Overlay

This directory mirrors a filesystem tree that is applied **on top of the base system** after image assembly and after installation. The overlay is how SeaBSD turns FreeBSD into SeaBSD: defaults, configuration snippets and branding live here, while the base system stays upstream-pure.

## Planned layout for v0.1

```text
overlay/
└── etc/
    ├── rc.conf.d/
    │   └── linux          # linux_enable="YES" + /compat/linux mount policy
    └── motd               # SeaBSD welcome text
```

## Rules

- Overlay files must be additive and self-contained: never require hand-editing of base system files.
- Every rc.conf.d snippet must carry a comment explaining the user-visible effect of each variable.
- Anything that does not fit the "defaults and snippets" model (new daemons, GUI tools) belongs in a port/package, not in the overlay.

## TODO (v0.1)

- Add `etc/rc.conf.d/linux` enabling the linuxolator with the SeaBSD mount policy (see `docs/linuxolator.md`).
- Add `etc/motd` with SeaBSD branding and a pointer to the documentation.
- Wire the overlay step into `build/build-iso.sh` release assembly.
- Decide the mechanism for preserving overlay changes across base updates.
