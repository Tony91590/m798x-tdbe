#!/usr/bin/env python3
"""Run actual service functions with temporary files and stubbed router APIs."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "package/mtk/applications"
SHELL = os.environ.get("TEST_SHELL", "/bin/sh")


class ShellTests(unittest.TestCase):
    def run_shell(self, script, env=None):
        result = subprocess.run(
            [SHELL], input=script, text=True, capture_output=True,
            env={**os.environ, **(env or {})}, timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.splitlines()

    def test_stop_does_not_stop_wifi_or_recurse(self):
        source = (APP / "luci-app-turboacc-mtk/root/etc/init.d/turboacc").read_text()
        rc = (ROOT / "package/base-files/files/etc/rc.common").read_text()
        # Exercise the real rc.common stop -> stop_service call chain.
        stop = re.search(r"\n\tstop\(\) \{.*?\n\t\}", rc, re.S).group()
        script = source + "\n" + stop + """
procd_lock() { :; }
procd_kill() { echo killed; }
set_hnat_enabled() { echo "hnat:$1"; }
ifconfig() { echo "unexpected-ifconfig:$*"; }
initscript=turboacc
stop
"""
        self.assertEqual(self.run_shell(script), ["hnat:0", "killed"])

    def test_start_preserves_unrelated_system_state(self):
        source = (APP / "luci-app-turboacc-mtk/root/etc/init.d/turboacc").read_text()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = ["sys/kernel/debug/hnat/hook_toggle", "proc/sys/vm/drop_caches",
                     "proc/sys/vm/min_free_kbytes", "etc/wgetrc",
                     "proc/sys/net/netfilter/nf_conntrack_nat_mode"]
            for name in paths:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("sentinel\n")
            firewall = root / "etc/init.d/firewall"
            firewall.parent.mkdir(parents=True, exist_ok=True)
            firewall.write_text("#!/bin/sh\nexit 0\n")
            firewall.chmod(0o755)
            # Redirect every absolute write in the sourced service to a temp tree.
            for prefix in ("/sys/", "/proc/", "/etc/"):
                source = source.replace(prefix, str(root) + prefix)
            script = source + """
config_load() { :; }
config_get() {
    case "$1" in
        fastpath) fastpath=none;;
        fullcone) fullcone=2;;
        tcpcca) tcpcca=cubic;;
        *) return 1;;
    esac
}
lsmod() { :; }
sysctl() { :; }
ifconfig() { echo 'error fetching interface information'; return 1; }
uci() { echo "unexpected-uci:$*"; return 1; }
start_service
"""
            output = self.run_shell(script)
            self.assertFalse(any("unexpected-uci:" in line for line in output))
            for name in paths[1:4]:
                self.assertEqual((root / name).read_text(), "sentinel\n")
            self.assertEqual((root / paths[0]).read_text(), "0\n")

    def test_wireless_setup_reports_failure_and_unlocks(self):
        source = (APP / "mtwifi-cfg/files/netifd/mtwifi.sh").read_text()
        source = source.replace(". /lib/netifd/netifd-wireless.sh", "")
        source = source.replace("/sbin/mtwifi_cfg", '"$TEST_CFG"')
        for failure in ("lan", "lock", "cfg", "none"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                cfg = Path(directory) / "cfg"
                cfg.write_text("#!/bin/sh\ncat >/dev/null\n[ \"$FAILURE\" != cfg ]\n")
                cfg.chmod(0o755)
                script = "init_wireless_driver() { :; }; add_driver() { :; }\n" + source + """
ubus() { [ "$FAILURE" != lan ]; }
lock() { echo "lock:$*"; [ "$FAILURE" != lock ]; }
logger() { :; }
json_add_string() { :; }
l1util() { echo rai; }
for_each_interface() { echo "interfaces:$*"; }
json_dump() { echo '{}'; }
wireless_set_up() { echo UP; }
wireless_setup_failed() { echo "FAILED:$1"; }
drv_mtwifi_setup radio5
echo "status:$?"
"""
                output = self.run_shell(script, {"FAILURE": failure, "TEST_CFG": str(cfg)})
                self.assertEqual(output[-1], "status:" + ("0" if failure == "none" else "1"))
                self.assertEqual("UP" in output, failure == "none")
                if failure in ("none", "cfg"):
                    self.assertIn("lock:-u /tmp/mtwifi.lock", output)
                if failure == "cfg":
                    self.assertNotIn("interfaces:ap mtwifi_vif_ap_config", output)
                    self.assertIn("FAILED:MTWIFI_SETUP_FAILED", output)


class LuaTests(unittest.TestCase):
    def test_lua_runtime(self):
        interpreters = os.environ.get("TEST_LUA", "luajit lua").split()
        interpreters = [exe for exe in interpreters if shutil.which(exe)]
        self.assertTrue(interpreters, "Install Lua 5.1 or LuaJIT to run the tests")
        cases = ["success", "invalid-json", "empty-input", "invalid-structure",
                 "unknown-device", "missing-profile", "invalid-encryption", "invalid-mode",
                 "invalid-htmode", "no-interfaces", "too-many-stations", "interface-failure",
                 "sleep", "sleep-error", "bounded-log"]
        for interpreter in interpreters:
            for case in cases:
                with self.subTest(interpreter=interpreter, case=case):
                    result = subprocess.run(
                        [interpreter, "tests/runtime/test_mtwifi.lua", case], cwd=ROOT,
                        text=True, capture_output=True, timeout=5,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
