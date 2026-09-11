import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from setup.model import HostConfig, NasDisk, NasParityDisk
from setup.features import nas
from setup.registry import Registry
from setup.render import render_consumer_flake, render_host
from setup.validation import device_path, disk_count, mount_options, network_interface
from setup.wizard import (
    configure_identity,
    configure_service_access,
    configure_service_inputs,
    show_summary,
    valid_service_input,
)


class SetupRendererTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registry = Registry(Path(__file__).resolve().parents[1])
        cls.registry.load()

    def test_media_starter_selects_only_core_services(self):
        state = {}
        self.registry.apply_preset(state, "media-starter")
        self.assertEqual(
            {
                service.service_id
                for service in self.registry.services
                if state.get(service.variable)
            },
            {
                "jellyfin",
                "seerr",
                "sonarr",
                "radarr",
                "prowlarr",
                "qbittorrent",
                "homepage",
                "nginx",
            },
        )
        host = HostConfig(repo_root=Path.cwd(), secrets_dir=Path("secrets"))
        host.service_preset = "media-starter"
        host.service_flags = state
        host.service_flags["ENABLE_SEERR"] = False
        rendered = render_host(host, self.registry)
        self.assertIn('nixstead.preset = "media-starter";', rendered)
        self.assertIn("nixstead.services.media.seerr.enable = false;", rendered)

    def test_standalone_flake_uses_only_public_program_modules(self):
        host = HostConfig(
            repo_root=Path("/srv/my-homelab"),
            secrets_dir=Path("/srv/my-homelab/secrets"),
            host_name="my-server",
        )
        host.program_flags = {"PROGRAM_CORE": True, "PROGRAM_ZSH": True}

        rendered = render_consumer_flake(host, "github:Kalmera74/nixstead")

        self.assertIn('nixosConfigurations."my-server"', rendered)
        self.assertIn("nixstead.nixosModules.default", rendered)
        self.assertIn("nixstead.nixosModules.program-core", rendered)
        self.assertIn("nixstead.nixosModules.program-zsh", rendered)
        self.assertNotIn("../../modules", rendered)
        subprocess.run(
            ["nix-instantiate", "--parse", "--expr", rendered],
            check=True,
            capture_output=True,
            text=True,
        )

    def test_standalone_configuration_owns_its_secret_path(self):
        host = HostConfig(
            repo_root=Path("/srv/my-homelab"),
            secrets_dir=Path("/srv/my-homelab/secrets"),
            host_name="my-server",
            user_name="admin",
            user_description="Admin",
            repository_path="/srv/my-homelab",
            system_state_version="25.05",
        )
        host.program_flags = {"PROGRAM_CORE": True}
        host.service_flags = {"ENABLE_VAULTWARDEN": True}

        rendered = render_host(host, self.registry, standalone=True)

        self.assertIn("sopsFile = ./secrets/my-server.yaml;", rendered)
        self.assertIn("nixstead.tools.enable = true;", rendered)
        self.assertNotIn("../../modules/programs", rendered)

        host.secrets_dir = Path("/run/private-nixstead-secrets")
        overridden = render_host(host, self.registry, standalone=True)
        self.assertNotIn("sopsFile =", overridden)

    def test_standalone_identity_accepts_a_not_yet_created_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "my-homelab"
            host = HostConfig(repo_root=output, secrets_dir=output / "secrets")

            class IdentityUI:
                def form(self, _title, _fields):
                    return {
                        "host_name": "my-server",
                        "user_name": "admin",
                        "user_description": "Admin",
                        "repository_path": str(output),
                    }

                def error(self, message):
                    raise AssertionError(message)

            with patch(
                "setup.wizard.pwd.getpwnam",
                return_value=SimpleNamespace(pw_uid=1000, pw_dir="/home/admin"),
            ):
                configure_identity(host, output, IdentityUI(), standalone=True)

            self.assertEqual(host.host_directory, output)
            self.assertEqual(host.repository_path, str(output))

    def test_selection_displays_coverage_and_storage_requirements(self):
        from unittest.mock import Mock
        from setup.wizard import show_preset_services

        host = HostConfig(repo_root=Path.cwd(), secrets_dir=Path("secrets"))
        host.service_flags = {"ENABLE_ROMM": True}
        ui = Mock()
        show_preset_services(host, self.registry, ui)
        displayed = ui.pager.call_args.args[0]
        self.assertIn("RomM", displayed)
        self.assertIn("ROM library", displayed)
        self.assertIn("MariaDB", displayed)
        self.assertIn("Borg marker restore smoke passed", displayed)

    def test_optional_catalog_collects_required_ingest(self):
        host = HostConfig(repo_root=Path.cwd(), secrets_dir=Path("secrets"))
        host.service_flags = {"ENABLE_SHELFMARK": True}

        class Form:
            def form(self, title, fields):
                return {fields[0][0]: "/srv/ingest/books"}

        configure_service_inputs(host, self.registry, Form())
        rendered = render_host(host, self.registry)
        self.assertIn('paths.ingestDir = "/srv/ingest/books";', rendered)
        self.assertEqual(
            host.service_settings["nixstead.services.arr.shelfmark.paths.ingestDir"],
            "/srv/ingest/books",
        )
        self.assertFalse(valid_service_input("/srv/../secret", "path"))
        host.service_flags["ENABLE_SHELFMARK"] = False
        self.assertNotIn("paths.ingestDir", render_host(host, self.registry))

    def test_missing_required_catalog_input_fails_before_generation(self):
        host = HostConfig(repo_root=Path.cwd(), secrets_dir=Path("secrets"))
        host.service_flags["ENABLE_SHELFMARK"] = True
        with self.assertRaisesRegex(ValueError, "requires an explicit value"):
            render_host(host, self.registry)

    def test_services_use_role_stacks_or_standalone_namespaces(self):
        expected = {
            "ENABLE_IMMICH": ("nixstead.services.media.immich.enable", "media-extra"),
            "ENABLE_ROMM": ("nixstead.services.media.romm.enable", "media-extra"),
            "ENABLE_TUBEARCHIVIST": (
                "nixstead.services.media.tubearchivist.enable",
                "media-extra",
            ),
            "ENABLE_UPTIMEKUMA": ("nixstead.services.dev.uptimekuma.enable", "dev"),
            "ENABLE_WALLABAG": (
                "nixstead.services.productivity.wallabag.enable",
                "productivity",
            ),
            "ENABLE_LINKWARDEN": (
                "nixstead.services.productivity.linkwarden.enable",
                "productivity",
            ),
            "ENABLE_VAULTWARDEN": (
                "nixstead.services.vaultwarden.enable",
                "standalone",
            ),
            "ENABLE_HOMEASSISTANT": (
                "nixstead.services.homeassistant.enable",
                "standalone",
            ),
            "ENABLE_AUTHENTIK": ("nixstead.services.authentik.enable", "standalone"),
        }

        for variable, (option_path, group) in expected.items():
            service = self.registry.by_variable(variable)
            self.assertEqual(service.option_path, option_path)
            self.assertEqual(service.group, group)

    def test_service_overrides_render_the_migrated_option_paths(self):
        host = HostConfig(
            repo_root=Path.cwd(),
            secrets_dir=Path("secrets"),
            host_name="service-paths",
            user_name="alice",
            user_description="Alice",
            user_uid=1000,
            repository_path=str(Path.cwd()),
            system_state_version="25.05",
        )
        host.service_flags = {
            "ENABLE_IMMICH": True,
            "ENABLE_UPTIMEKUMA": True,
            "ENABLE_LINKWARDEN": True,
            "ENABLE_VAULTWARDEN": True,
            "ENABLE_HOMEASSISTANT": True,
            "ENABLE_AUTHENTIK": True,
        }

        rendered = render_host(host, self.registry)

        self.assertIn("nixstead.services.media.immich.enable = true;", rendered)
        self.assertIn("nixstead.services.dev.uptimekuma.enable = true;", rendered)
        self.assertIn(
            "nixstead.services.productivity.linkwarden.enable = true;", rendered
        )
        self.assertIn("nixstead.services.vaultwarden.enable = true;", rendered)
        self.assertIn("nixstead.services.homeassistant.enable = true;", rendered)
        self.assertIn("nixstead.services.authentik.enable = true;", rendered)

    def test_nas_layout_is_rendered_as_structured_options(self):
        host = HostConfig(
            repo_root=Path.cwd(),
            secrets_dir=Path("secrets"),
            host_name="test",
            user_name="alice",
            user_description="Alice",
            user_uid=1000,
            repository_path=str(Path.cwd()),
            system_state_version="25.05",
        )
        host.nas.enabled = True
        host.nas.data = [NasDisk("data1", "/dev/disk/by-id/data", "/mnt/data1", "ext4")]
        host.nas.parity = [
            NasParityDisk("/dev/disk/by-id/parity", "/mnt/parity", "ext4")
        ]

        rendered = render_host(host, self.registry)

        self.assertIn("nixstead.services.nas = {", rendered)
        self.assertIn("mergerfs.enable = true;", rendered)
        self.assertIn("snapraid.enable = true;", rendered)
        self.assertIn("samba.enable = true;", rendered)
        self.assertIn('name = "data1";', rendered)
        self.assertIn('device = "/dev/disk/by-id/parity";', rendered)
        self.assertNotIn("nixstead.services.nas.enable =", rendered)

    def test_storage_validators_reject_ambiguous_inputs(self):
        self.assertTrue(device_path("/dev/disk/by-id/data"))
        self.assertFalse(device_path("/dev/sda 1"))
        self.assertTrue(disk_count("2"))
        self.assertFalse(disk_count("0"))
        self.assertTrue(mount_options("nofail,x-systemd.automount"))
        self.assertFalse(mount_options("nofail;mkfs"))
        self.assertTrue(network_interface("enp3s0.20"))
        self.assertFalse(network_interface("enp3s0;open"))

    def test_nginx_lan_exposure_is_rendered_deliberately(self):
        host = HostConfig(
            repo_root=Path.cwd(),
            secrets_dir=Path("secrets"),
            host_name="lan-test",
            user_name="alice",
            user_description="Alice",
            repository_path=str(Path.cwd()),
            system_state_version="25.05",
        )
        host.service_flags["ENABLE_NGINX"] = True
        host.service_access = "lan"
        host.lan_interface = "enp3s0"
        host.lan_source_cidr = "192.168.50.0/24"

        rendered = render_host(host, self.registry)

        self.assertIn('services.nginx = "lan";', rendered)
        self.assertIn('"enp3s0"', rendered)
        self.assertIn('"192.168.50.0/24"', rendered)

    def test_nginx_loopback_exposure_is_explicit(self):
        host = HostConfig(
            repo_root=Path.cwd(),
            secrets_dir=Path("secrets"),
            host_name="local-test",
            user_name="alice",
            user_description="Alice",
            repository_path=str(Path.cwd()),
            system_state_version="25.05",
        )
        host.service_flags["ENABLE_NGINX"] = True

        rendered = render_host(host, self.registry)

        self.assertIn('services.nginx = "loopback";', rendered)

    def test_public_exposure_requires_confirmation(self):
        host = HostConfig(repo_root=Path.cwd(), secrets_dir=Path("secrets"))
        host.service_flags["ENABLE_NGINX"] = True

        class RejectPublicUI:
            def __init__(self):
                self.selections = iter([3, 0])
                self.defaults = []
                self.warning = ""

            def select(self, _prompt, _choices, default):
                self.defaults.append(default)
                return next(self.selections)

            def pager(self, message):
                self.warning = message

            def yes_no(self, _prompt, _default):
                return False

        ui = RejectPublicUI()
        configure_service_access(host, ui)

        self.assertEqual(ui.defaults, [0, 0])
        self.assertIn("PUBLIC EXPOSURE WARNING", ui.warning)
        self.assertEqual(host.service_access, "loopback")

    def test_final_review_shows_lan_exposure_selectors(self):
        host = HostConfig(repo_root=Path.cwd(), secrets_dir=Path("secrets"))
        host.service_flags["ENABLE_NGINX"] = True
        host.service_access = "lan"
        host.lan_interface = "enp3s0"
        host.lan_source_cidr = "192.168.50.0/24"

        class ReviewUI:
            content = ""

            def pager(self, content):
                self.content = content

        ui = ReviewUI()
        show_summary(host, self.registry, ui)

        self.assertIn(
            "Service access: LAN (interface enp3s0, source 192.168.50.0/24)", ui.content
        )

    def test_ssh_policy_is_rendered_with_the_firewall_port(self):
        host = HostConfig(
            repo_root=Path.cwd(),
            secrets_dir=Path("secrets"),
            host_name="ssh-test",
            user_name="alice",
            user_description="Alice",
            user_uid=1000,
            repository_path=str(Path.cwd()),
            system_state_version="25.05",
        )
        host.ssh.port = 2222
        host.ssh.authorized_key = (
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample alice@example"
        )
        host.ssh.password_authentication = False
        host.ssh.root_login = "prohibit-password"

        rendered = render_host(host, self.registry)

        self.assertIn("ports.ssh = 2222;", rendered)
        self.assertIn('rootLogin = "prohibit-password";', rendered)
        self.assertIn("passwordAuthentication = false;", rendered)
        self.assertIn(host.ssh.authorized_key, rendered)

    def test_cifs_render_keeps_mount_sources_in_the_host(self):
        host = HostConfig(
            repo_root=Path.cwd(),
            secrets_dir=Path("secrets"),
            host_name="cifs-test",
            user_name="alice",
            user_description="Alice",
            user_uid=1000,
            repository_path=str(Path.cwd()),
            system_state_version="25.05",
        )
        host.cifs.enabled = True
        host.cifs.server = "192.0.2.10"
        host.cifs.media_source = "//192.0.2.10/Media"
        host.cifs.media_mount = "/srv/media"
        host.cifs.media = True
        host.service_flags["ENABLE_QBITTORRENT"] = True

        rendered = render_host(host, self.registry)

        self.assertIn('source = "//192.0.2.10/Media";', rendered)
        self.assertIn('mountPoint = "/srv/media";', rendered)
        self.assertIn(
            'nixstead.services.arr.qbittorrent.paths.savePath = "${config.nixstead.services.cifs.shares.media.mountPoint}/data/torrents";',
            rendered,
        )
        self.assertIn(
            'nixstead.services.arr.qbittorrent.paths.tempPath = "${config.nixstead.services.cifs.shares.media.mountPoint}/data/torrents/temp";',
            rendered,
        )
        self.assertNotIn('server = "192.0.2.10";', rendered)

    def test_nas_discovery_reports_disk_details_and_ignores_swap(self):
        lsblk = {
            "blockdevices": [
                {
                    "path": "/dev/sdb",
                    "type": "disk",
                    "size": 1000 * 1024 * 1024 * 1024,
                    "fstype": None,
                    "uuid": None,
                    "mountpoint": None,
                    "fsavail": None,
                    "model": "NAS DISK",
                },
                {
                    "path": "/dev/zram0",
                    "type": "disk",
                    "size": 8 * 1024 * 1024 * 1024,
                    "fstype": "swap",
                    "uuid": "swap",
                    "mountpoint": "[SWAP]",
                },
            ]
        }
        with (
            patch("setup.features.nas.output", return_value=json.dumps(lsblk)),
            patch("setup.features.nas._stable_path", side_effect=lambda value: value),
        ):
            disks = nas.discover_disks()

        self.assertEqual([disk.path for disk in disks], ["/dev/sdb"])
        self.assertEqual(disks[0].free_bytes, disks[0].size_bytes)
        self.assertIn("size 1000.0 GiB", disks[0].label)
        self.assertIn("free 1000.0 GiB", disks[0].label)
        self.assertIn("UUID none", disks[0].label)

    def test_nas_can_be_disabled_when_no_disk_is_available(self):
        host = HostConfig(repo_root=Path.cwd(), secrets_dir=Path("secrets"))

        class NoDiskUI:
            def header(self, *args):
                pass

            def pager(self, *args):
                pass

            def yes_no(self, *args, **kwargs):
                return True

        with patch("setup.features.nas.discover_disks", return_value=[]):
            self.assertFalse(nas.configure(host, NoDiskUI()))
        self.assertFalse(host.nas.enabled)
        self.assertFalse(host.nas.configured)


if __name__ == "__main__":
    unittest.main()
