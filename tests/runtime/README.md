# Runtime script regression tests

Run from the repository root:

```sh
python3 tests/runtime/test_runtime.py
```

Requirements: Python 3, a POSIX shell, and Lua 5.1 or LuaJIT. By default the
runner uses available `luajit` and `lua` executables. Override with `TEST_LUA`
(space-separated executables) and `TEST_SHELL` (one shell executable path).
The CI workflow uses Lua 5.1, LuaJIT and BusyBox ash.

The tests execute the real Lua configuration generator and shell service
functions with mocked native modules, commands, profile storage and netifd
notifications. Service filesystem writes are redirected into temporary trees.
They do not access a router, modify host network settings or load kernel modules.
All credentials are synthetic fixtures.

Coverage:

- A valid WPA3/EHT configuration still produces the expected encryption and PMF
  settings and starts the AP interface.
- Invalid/empty input, missing profiles, unsupported encryption, invalid wireless
  modes and interface failures propagate to a nonzero exit status.
- Neither input values nor old/new keys appear in diagnostics; summaries are
  bounded in size.
- Interrupted sleeps resume the remaining duration without busy waiting.
- The real rc.common stop callback completes without shutting down Wi-Fi or
  recursively calling stop.
- Starting turboacc does not clear caches, change memory watermarks or rewrite
  wget preferences, and does not commit unrelated firewall edits.
- Failed netifd setup releases the acquired lock and never reports the radio up.

These tests are not a firmware build or hardware qualification. They do not
prove radio throughput, group-key operation, multicast delivery or recovery
from a partially completed driver reload.
