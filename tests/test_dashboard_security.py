"""Static regression checks for legacy dashboard security boundaries.

These contracts require a separate runtime acceptance pass on the NIO.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DashboardSecurityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compose = (ROOT / "dashboard/docker-compose.yml").read_text()
        cls.caddy = (ROOT / "dashboard/config/caddy/Caddyfile").read_text()
        cls.installer = (ROOT / "dashboard/setup-dashboard.sh").read_text()

    def test_docker_socket_is_not_mounted_anywhere(self):
        self.assertNotIn("/var/run/docker.sock", self.compose)
        self.assertNotIn("docker-socket-proxy", self.compose)

    def test_only_loopback_dashboard_is_published_by_default(self):
        self.assertIn("${NIO_DASHBOARD_BIND:-127.0.0.1}:80:80", self.compose)
        self.assertNotIn('"3000:3000"', self.compose)
        self.assertNotIn('"19999:19999"', self.compose)
        self.assertNotIn('"443:443"', self.compose)

    def test_host_monitoring_is_not_unconfined(self):
        self.assertNotIn("- SYS_PTRACE", self.compose)
        self.assertNotIn("apparmor:unconfined", self.compose)
        self.assertIn("no-new-privileges:true", self.compose)

    def test_caddy_does_not_proxy_host_monitoring(self):
        self.assertNotIn("reverse_proxy netdata:", self.caddy)
        self.assertIn("reverse_proxy homepage:3000", self.caddy)

    def test_installer_avoids_remote_shell_install_and_unattended_cockpit(self):
        self.assertNotIn("get.docker.com", self.installer)
        self.assertIn('NIO_ENABLE_COCKPIT:-0', self.installer)

    def test_native_netdata_only_binds_loopback(self):
        native = (ROOT / "dashboard/config/netdata/netdata.conf").read_text()
        self.assertIn("bind to = 127.0.0.1", native)
        self.assertNotIn("bind socket to = *", native)
        self.assertNotIn("/etc/netdata:/etc/netdata:ro", self.compose)

    def test_legacy_optimizer_does_not_open_management_services(self):
        optimizer = (ROOT / "setup/optimize-system.sh").read_text()
        self.assertNotIn("netdata-kickstart.sh", optimizer)
        self.assertNotIn("my-netdata.io/kickstart.sh", optimizer)
        self.assertIn('NIO_ENABLE_COCKPIT:-0', optimizer)
        self.assertNotIn('apt-get install -y docker.io', optimizer)


if __name__ == "__main__":
    unittest.main()
