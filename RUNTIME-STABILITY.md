# Runtime stability changes

This branch improves runtime scripts without changing radio defaults,
encryption modes, channel selection, driver binaries or flash layout.

## Changes

- Stopping turboacc disables its HNAT hook without stopping either radio or
  re-entering rc.common's stop callback. Startup applies the configured HNAT
  state without an unconditional off/on pulse.
- Turboacc no longer commits unrelated firewall changes, forces wget to IPv4,
  changes the memory watermark or drops filesystem caches on every reload.
- mtwifi-cfg logs changed field names to syslog instead of dumping complete
  input and old/new configuration values into an unbounded temporary file.
  Existing `/tmp/mtwifi.log` files from an older version are not migrated or
  uploaded by this change; handle old diagnostics as potentially sensitive.
- Driver initialization uses blocking nanosleep with interrupted-sleep handling.
- Known invalid configurations, unavailable profiles and interface command
  failures return failure to netifd instead of unconditionally announcing that
  wireless setup succeeded. Nixio is now an explicit package dependency.
- Host regression tests cover these paths with synthetic data and isolated I/O.

## Validation before deployment

Run the host tests, build the affected packages/full image in the matching
OpenWrt build environment, then test on a device with wired management access.
Check service start/stop/reload, WPA3 association, multiple SSIDs, AP-client mode,
new-client DHCP, same-radio and cross-radio traffic, IPv6 and multicast discovery.
This branch does not implement transactional rollback after a partially
completed radio/driver reload.

## Follow-up work

The AP-mode migration inside turboacc still needs to be separated into an
explicit migration operation with discovered interface names, validation and
rollback. This branch does not change that feature's network topology behavior.
Firmware release defaults/documentation and feed pinning also need separate
review.

The reported same-radio ARP/broadcast problem is not claimed to be fixed in the
driver. A bridge ARP proxy can help affected IPv4 clients, but should not be
enabled globally without testing cold caches, new devices, guest isolation,
IPv6 and multicast. No ARP workaround is forced on every user by this branch.
