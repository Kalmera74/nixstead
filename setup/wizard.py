from __future__ import annotations

import getpass
import os
import pwd
import socket
import subprocess
from collections.abc import Callable, Sequence
from pathlib import Path

from .commands import exists, output
from .features import nas, ssh
from .model import HostConfig
from .registry import Registry
from .ui import SectionBack, UI
from .validation import (
    absolute_path,
    host_name,
    ipv4,
    ipv4_cidr,
    network_interface,
    repository_path,
    timezone,
    unsigned,
    user_name,
)


PRESET_DESCRIPTIONS = {
    "media-starter": "Recommended streaming start: Jellyfin, Seerr, Sonarr, Radarr, Prowlarr, qBittorrent, Homepage and Nginx. Plan 4 CPU cores, 8 GiB RAM and separate media/backup capacity; transcoding needs depend on your media. Partial runtime coverage; see each service below.",
    "minimal": "Core platform services for a small, general-purpose NixOS host.",
    "media-server": "Extended catalog including photos, ROMs, archival, reading and transcoding; several services have evaluation-only coverage. Review each service before enabling.",
    "development": "Development databases, observability, queues, and local development services.",
    "full": "Advanced/demo role enabling the complete media, development, platform, productivity, and AI catalog; not recommended for a first host.",
    "custom": "Start with preset-controlled services disabled and choose exactly what to enable.",
}
PRESET_LABELS = {
    "media-starter": "Media starter (recommended)",
    "media-server": "Media server (extended catalog)",
    "full": "Full (advanced/demo)",
}
PRESET_NAMES = tuple(PRESET_DESCRIPTIONS)


def validated_form(
    ui: UI,
    title: str,
    fields: Sequence[tuple[str, str, str, str]],
    validators: Sequence[tuple[str, Callable[[str], bool], str]],
) -> dict[str, str]:
    """Collect a group of values and repeat the page when one is invalid."""

    current = list(fields)
    while True:
        values = ui.form(title, current)
        for key, validator, message in validators:
            if not validator(values[key]):
                ui.error(message.format(value=values[key] or "<empty>"))
                current = [
                    (field_key, label, values.get(field_key, default), help_text)
                    for field_key, label, default, help_text in current
                ]
                break
        else:
            return values


def detect_user() -> str:
    return os.environ.get("SUDO_USER") or getpass.getuser() or "nixos"


def detect_free_uid(start: int = 1000) -> int:
    used_uids = {entry.pw_uid for entry in pwd.getpwall()}
    uid = max(start, 1000)
    while uid in used_uids:
        uid += 1
    return uid


def detect_host() -> str:
    return (socket.gethostname() or "nixos").split(".", 1)[0]


def detect_ipv4() -> str:
    try:
        address = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        address.connect(("1.1.1.1", 80))
        result = address.getsockname()[0]
        address.close()
        return result
    except OSError:
        return ""


def detect_timezone() -> str:
    try:
        return (
            output(["timedatectl", "show", "--property=Timezone", "--value"]) or "UTC"
        )
    except (OSError, subprocess.CalledProcessError):
        return "UTC"


def detect_router() -> str:
    try:
        for line in output(["ip", "-4", "route", "show", "default"]).splitlines():
            fields = line.split()
            if "via" in fields:
                return fields[fields.index("via") + 1]
    except (OSError, subprocess.CalledProcessError, ValueError):
        pass
    return ""


def detect_tailscale_ip() -> str:
    try:
        return output(["tailscale", "ip", "-4"]).splitlines()[0]
    except (OSError, subprocess.CalledProcessError, IndexError):
        return ""


def detect_gpu() -> str:
    try:
        vendors = " ".join(
            Path(path).read_text().strip()
            for path in Path("/sys/class/drm").glob("card*/device/vendor")
        )
    except OSError:
        vendors = ""
    if "0x10de" in vendors:
        return "cuda"
    if "0x1002" in vendors:
        return "rocm"
    return "none"


def detect_authorized_key(user: str) -> str:
    try:
        import pwd

        path = Path(pwd.getpwnam(user).pw_dir) / ".ssh/authorized_keys"
        for line in path.read_text().splitlines():
            if line.startswith(("ssh-ed25519 ", "ssh-rsa ", "ecdsa-", "sk-")):
                return line
    except (KeyError, OSError):
        pass
    return ""


def initial_state(repo_root: Path, secrets_dir: Path) -> HostConfig:
    user = detect_user()
    try:
        uid = int(output(["id", "-u", user]))
    except (OSError, subprocess.CalledProcessError, ValueError):
        uid = 1000
    host = HostConfig(
        repo_root=repo_root,
        secrets_dir=secrets_dir,
        host_name=detect_host(),
        user_name=user,
        user_description=user,
        user_uid=uid,
        repository_path=str(repo_root),
        time_zone=detect_timezone(),
        lan_ip=detect_ipv4(),
        router_ip=detect_router(),
        tailscale_ip=detect_tailscale_ip(),
        gpu_acceleration=detect_gpu(),
        bootloader="systemd-boot" if Path("/sys/firmware/efi").is_dir() else "grub",
        audio=Path("/dev/snd").exists() or Path("/proc/asound").is_dir(),
        bluetooth=any(Path("/sys/class/bluetooth").glob("hci*")),
    )
    host.sync_user_paths()
    host.user_groups = {
        "USER_WHEEL": True,
        "USER_NETWORKMANAGER": True,
        "USER_DOCKER": False,
        "USER_WIRESHARK": False,
    }
    host.program_flags = {
        "PROGRAM_CORE": True,
        "PROGRAM_DEVELOPMENT": False,
        "PROGRAM_HARDWARE": True,
        "PROGRAM_NETWORKING": True,
        "PROGRAM_MEDIA": False,
        "PROGRAM_BACKUP": False,
        "PROGRAM_ZSH": True,
        "PROGRAM_YAZI": True,
    }
    return host


def configure_identity(
    host: HostConfig, repo_root: Path, ui: UI, *, standalone: bool = False
) -> None:
    current_system_user = host.user_name
    while True:
        values = validated_form(
            ui,
            "Identity",
            [
                (
                    "host_name",
                    "Host/flake name",
                    host.host_name,
                    (
                        "Names the generated flake target."
                        if standalone
                        else "Creates hosts/<name> and the matching flake target."
                    ),
                ),
                (
                    "user_name",
                    "Primary user name",
                    host.user_name,
                    "The main login account this configuration manages.",
                ),
                (
                    "user_description",
                    "User description/full name",
                    host.user_description,
                    "Shown as the display name for the primary account.",
                ),
                (
                    "repository_path",
                    "Configuration path on this machine",
                    host.repository_path,
                    (
                        "Absolute path to the generated consumer flake."
                        if standalone
                        else "Absolute path to this clone."
                    ),
                ),
            ],
            [
                ("host_name", host_name, "Invalid host name: {value}"),
                ("user_name", user_name, "Invalid user name: {value}"),
                (
                    "repository_path",
                    absolute_path if standalone else repository_path,
                    "Invalid repository path: {value}",
                ),
            ],
        )
        host.host_name = values["host_name"]
        host.host_directory = (
            repo_root if standalone else repo_root / "hosts" / host.host_name
        )
        if not standalone and host.host_directory.exists():
            ui.error(f"Host already exists: {host.host_directory}")
            continue
        host.user_name = values["user_name"]
        host.user_description = values["user_description"]
        host.repository_path = values["repository_path"]
        requested_existing_user = host.user_name == current_system_user
        try:
            existing = pwd.getpwnam(host.user_name)
            host.user_uid = existing.pw_uid
            host.user_existed_before = True
        except KeyError:
            if not requested_existing_user and not ui.yes_no(
                f"Primary user '{host.user_name}' does not exist. Create it automatically?",
                True,
            ):
                continue
            host.user_existed_before = False
            host.user_uid = detect_free_uid()
        host.created_user = host.user_name
        host.sync_user_paths()
        return


def choose_preset(ui: UI) -> str:
    choices = [
        f"{PRESET_LABELS.get(name, name.replace('-', ' ').title())}|{description}"
        for name, description in PRESET_DESCRIPTIONS.items()
    ]
    return PRESET_NAMES[ui.select("Choose a starting service role", choices, 0)]


def show_preset_services(host: HostConfig, registry: Registry, ui: UI) -> None:
    enabled = [
        service.selection_label
        for service in registry.services
        if host.service_flags.get(service.variable, False)
    ]
    lines = [
        f"Preset: {host.service_preset.replace('-', ' ').title()}",
        PRESET_DESCRIPTIONS[host.service_preset],
        "",
        "Foundation: NetworkManager, SSH/firewall port, configured locale and timezone.",
        "The wizard manages the selected user, groups and shell. Review these before switching.",
        "Existing servers can instead import nixosModules.services or individual stacks.",
        "",
        "Services that will be enabled:",
    ]
    if enabled:
        lines.extend(f"  • {label}" for label in enabled)
    else:
        lines.append("  (none)")
    ui.pager("\n".join(lines))


def apply_role_defaults(host: HostConfig, registry: Registry, preset: str) -> None:
    host.service_preset = preset
    registry.apply_preset(host.service_flags, preset)
    if preset == "media-server":
        host.program_flags.update({"PROGRAM_MEDIA": True, "PROGRAM_BACKUP": True})
    elif preset == "development":
        host.program_flags["PROGRAM_DEVELOPMENT"] = True
    elif preset == "full":
        host.program_flags.update(
            {"PROGRAM_DEVELOPMENT": True, "PROGRAM_MEDIA": True, "PROGRAM_BACKUP": True}
        )


def choose_service_start(
    host: HostConfig, registry: Registry, ui: UI, initialized: bool
) -> bool:
    if not initialized:
        apply_role_defaults(host, registry, choose_preset(ui))
    else:
        choices = ["Keep current choices|Review the services currently selected"]
        choices.extend(
            f"{PRESET_LABELS.get(name, name.replace('-', ' ').title())}|{description}"
            for name, description in PRESET_DESCRIPTIONS.items()
        )
        selection = ui.select("Service preset", choices, 0)
        if selection != 0:
            apply_role_defaults(host, registry, PRESET_NAMES[selection - 1])
    show_preset_services(host, registry, ui)
    return ui.yes_no(
        "Modify the preset's enabled services and program modules",
        host.service_preset == "custom",
    )


def configure_services(
    host: HostConfig, registry: Registry, ui: UI, initialized: bool
) -> None:
    if not choose_service_start(host, registry, ui, initialized):
        configure_service_inputs(host, registry, ui)
        return
    groups = [
        ("ARR services", [*registry.groups("arr")]),
        (
            "Media services",
            [*registry.groups("media-core"), *registry.groups("media-extra")],
        ),
        ("Development and monitoring services", [*registry.groups("dev")]),
        ("Local AI services", [*registry.groups("localai")]),
        ("Productivity services", [*registry.groups("productivity")]),
        ("Standalone services", [*registry.groups("standalone")]),
        ("Platform services", [*registry.groups("platform")]),
    ]
    for label, services in groups:
        ui.checklist(
            label,
            [(service.variable, service.selection_label) for service in services],
            host.service_flags,
        )
    ui.checklist(
        "Program modules",
        [
            (key, key.removeprefix("PROGRAM_").replace("_", " ").title())
            for key in host.program_flags
        ],
        host.program_flags,
    )
    configure_service_inputs(host, registry, ui)


def valid_service_input(value: str, kind: str) -> bool:
    return (
        kind == "path"
        and value.startswith("/")
        and all(part not in {"", ".", ".."} for part in value.split("/")[1:])
    )


def configure_service_inputs(host: HostConfig, registry: Registry, ui: UI) -> None:
    for service in registry.services:
        if not host.service_flags.get(service.variable, False):
            continue
        for service_id in service.requires_services:
            required = next(
                item for item in registry.services if item.service_id == service_id
            )
            host.service_flags[required.variable] = True
        for item in service.inputs:
            path = "nixstead.services." + ".".join(item["optionPath"])
            default = host.service_settings.get(path, "")
            values = validated_form(
                ui,
                service.label,
                [(path, item["label"], default, item["help"])],
                [
                    (
                        path,
                        lambda value, kind=item["kind"]: valid_service_input(
                            value, kind
                        ),
                        "Supply a normalized absolute path.",
                    )
                ],
            )
            host.service_settings[path] = values[path]


def configure_infrastructure_selection(
    host: HostConfig, registry: Registry, ui: UI
) -> None:
    selected = {"USE_MANAGED_SWITCH": host.use_managed_switch}
    items = [("USE_MANAGED_SWITCH", "Managed network switch")]
    for service in registry.groups("integration"):
        items.append((service.variable, service.label))
        selected[service.variable] = host.service_flags.get(service.variable, False)
    ui.checklist("Select external infrastructure and storage", items, selected)
    host.use_managed_switch = selected["USE_MANAGED_SWITCH"]
    for service in registry.groups("integration"):
        host.service_flags[service.variable] = selected[service.variable]
    if not host.service_flags.get("ENABLE_CIFS", False):
        host.cifs.enabled = False
    if not host.service_flags.get("ENABLE_NAS", False):
        host.nas.enabled = False


def configure_service_access(host: HostConfig, ui: UI) -> None:
    if not host.service_flags.get("ENABLE_NGINX", False):
        host.service_access = "loopback"
        host.lan_interface = ""
        host.lan_source_cidr = ""
        return

    modes = ["loopback", "lan", "tailnet", "public"]
    choices = [
        "Local machine only|Keep Nginx on loopback; other devices cannot connect",
        "LAN|Allow trusted local-network access through a selected interface or source CIDR",
        "Tailscale|Allow access through the tailscale0 interface",
        "Public internet (advanced)|Open HTTP/HTTPS on every interface; external firewall, DNS, and TLS planning are required",
    ]
    while True:
        selected = modes[
            ui.select(
                "How should other devices reach services through Nginx?",
                choices,
                modes.index(host.service_access),
            )
        ]
        if selected == "public":
            ui.pager(
                "PUBLIC EXPOSURE WARNING\n\n"
                "This opens the configured HTTP and HTTPS ports on every network interface. "
                "The wizard does not configure router port forwarding, public DNS, or a publicly trusted TLS certificate."
            )
            if not ui.yes_no("Confirm unrestricted Nginx firewall exposure", False):
                continue

        host.service_access = selected
        host.lan_interface = ""
        host.lan_source_cidr = ""
        if selected == "lan":
            while True:
                values = validated_form(
                    ui,
                    "LAN service exposure",
                    [
                        (
                            "interface",
                            "LAN interface, if restricting by interface",
                            host.lan_interface,
                            "For example enp3s0; either this or a source CIDR is required.",
                        ),
                        (
                            "source_cidr",
                            "Trusted LAN source CIDR, if restricting by network",
                            host.lan_source_cidr,
                            "For example 192.168.1.0/24; either this or an interface is required.",
                        ),
                    ],
                    [
                        (
                            "interface",
                            lambda value: not value or network_interface(value),
                            "Invalid network interface: {value}",
                        ),
                        (
                            "source_cidr",
                            lambda value: not value or ipv4_cidr(value),
                            "Invalid LAN source CIDR: {value}",
                        ),
                    ],
                )
                if not values["interface"] and not values["source_cidr"]:
                    ui.error(
                        "LAN exposure requires an interface or a trusted source CIDR."
                    )
                    continue
                host.lan_interface = values["interface"]
                host.lan_source_cidr = values["source_cidr"]
                break
        elif selected == "tailnet":
            if not host.service_flags.get("ENABLE_TAILSCALE", False):
                host.service_flags["ENABLE_TAILSCALE"] = True
                ui.pager(
                    "Tailscale has been enabled because Nginx was assigned to tailnet access."
                )
        return


def configure_network(host: HostConfig, registry: Registry, ui: UI) -> None:
    lan_label = (
        "LAN/service IPv4 address"
        if registry.requires_lan(host.service_flags)
        else "LAN/service IPv4 address, if needed"
    )
    lan_help = (
        "Stable address used in service URLs and dashboard widgets."
        if registry.requires_lan(host.service_flags)
        else "Optional when no selected application publishes a LAN service."
    )
    lan_validator = (
        ipv4
        if registry.requires_lan(host.service_flags)
        else lambda value: not value or ipv4(value)
    )
    values = validated_form(
        ui,
        "Locale and network addresses",
        [
            (
                "time_zone",
                "Time zone",
                host.time_zone,
                "Use an IANA zone such as Europe/Istanbul or America/New_York.",
            ),
            (
                "default_locale",
                "Default locale",
                host.default_locale,
                "System-wide language and character encoding.",
            ),
            (
                "console_keymap",
                "Console keymap",
                host.console_keymap,
                "Linux virtual-console keymap, for example us, uk, de, or trq.",
            ),
            ("lan_ip", lan_label, host.lan_ip, lan_help),
            (
                "router_ip",
                "Router IPv4 address",
                host.router_ip,
                "Optional gateway or router-dashboard address.",
            ),
        ],
        [
            ("time_zone", timezone, "Invalid time zone: {value}"),
            ("lan_ip", lan_validator, "Invalid IPv4 address: {value}"),
            (
                "router_ip",
                lambda value: not value or ipv4(value),
                "Invalid router IPv4 address: {value}",
            ),
        ],
    )
    host.time_zone = values["time_zone"]
    host.default_locale = values["default_locale"]
    host.console_keymap = values["console_keymap"]
    host.lan_ip = values["lan_ip"]
    host.router_ip = values["router_ip"]
    configure_service_access(host, ui)
    detected_key = detect_authorized_key(host.user_name)
    ssh.configure(host, ui, detected_key)


def configure_hardware(host: HostConfig, ui: UI) -> None:
    default_boot = {"systemd-boot": 0, "grub": 1, "none": 2}.get(
        host.bootloader, 1 if not Path("/sys/firmware/efi").exists() else 0
    )
    host.bootloader = ["systemd-boot", "grub", "none"][
        ui.select(
            "Choose the bootloader",
            [
                "systemd-boot (UEFI)",
                "GRUB (explicit installation device required)",
                "Do not manage a bootloader",
            ],
            default_boot,
        )
    ]
    if host.bootloader == "grub":
        from .validation import grub_device

        while True:
            values = validated_form(
                ui,
                "GRUB installation",
                [
                    (
                        "grub_device",
                        "GRUB installation device",
                        host.grub_device or "nodev",
                        "Enter a whole disk such as /dev/nvme0n1, or nodev for an image-style install.",
                    )
                ],
                [("grub_device", grub_device, "Invalid GRUB device: {value}")],
            )
            host.grub_device = values["grub_device"]
            if host.grub_device != "nodev" and exists("lsblk"):
                subprocess.run(
                    ["lsblk", "-dn", "-o", "NAME,SIZE,TYPE,MODEL", host.grub_device],
                    check=False,
                )
            if ui.yes_no(f"Confirm the GRUB target {host.grub_device}", False):
                break
    host.grub_use_os_prober = (
        ui.yes_no(
            "Enable GRUB OS probing for other operating systems",
            host.grub_use_os_prober,
        )
        if host.bootloader == "grub"
        else False
    )
    hardware = {
        "ENABLE_AUDIO": host.audio,
        "ENABLE_BLUETOOTH": host.bluetooth,
        "ENABLE_ALL_FIRMWARE": host.all_firmware,
        "ENABLE_SWAP": host.swap_enabled,
    }
    ui.checklist(
        "Select hardware features",
        [
            ("ENABLE_AUDIO", "Audio support"),
            ("ENABLE_BLUETOOTH", "Bluetooth support"),
            ("ENABLE_ALL_FIRMWARE", "All redistributable firmware"),
            ("ENABLE_SWAP", "Swap file"),
        ],
        hardware,
    )
    host.audio = hardware["ENABLE_AUDIO"]
    host.bluetooth = hardware["ENABLE_BLUETOOTH"]
    host.all_firmware = hardware["ENABLE_ALL_FIRMWARE"]
    host.swap_enabled = hardware["ENABLE_SWAP"]
    if host.swap_enabled:
        current_gib = host.swap_size_mib // 1024 or 8
        values = validated_form(
            ui,
            "Swap file",
            [
                (
                    "swap_device",
                    "Swap file path",
                    host.swap_device,
                    "Absolute path where NixOS should create and manage the swap file.",
                ),
                (
                    "swap_size_gib",
                    "Swap size in GiB",
                    str(current_gib),
                    "Whole number of gibibytes; must be greater than zero.",
                ),
            ],
            [
                ("swap_device", absolute_path, "Invalid swap path: {value}"),
                (
                    "swap_size_gib",
                    lambda value: unsigned(value) and int(value) > 0,
                    "Swap size must be greater than zero: {value}",
                ),
            ],
        )
        host.swap_device = values["swap_device"]
        current_gib = int(values["swap_size_gib"])
        host.swap_size_mib = current_gib * 1024
    host.gpu_acceleration = ["none", "cuda", "rocm"][
        ui.select(
            "Choose GPU acceleration",
            ["None / CPU only", "NVIDIA CUDA", "AMD ROCm"],
            {"none": 0, "cuda": 1, "rocm": 2}.get(host.gpu_acceleration, 0),
        )
    ]


def configure_selected_details(
    host: HostConfig, registry: Registry, ui: UI, shares_initialized: bool
) -> bool:
    address_fields: list[tuple[str, str, str, str]] = []
    if host.use_managed_switch:
        address_fields.append(
            (
                "switch_ip",
                "Switch management IPv4 address",
                host.switch_ip,
                "Address used by the Homepage link for the managed switch.",
            )
        )
    if host.service_flags.get("ENABLE_PIHOLE", False):
        address_fields.append(
            (
                "pihole_ip",
                "Pi-hole IPv4 address",
                host.pihole_ip,
                "Address of the existing Pi-hole instance.",
            )
        )
    if host.service_flags.get("ENABLE_PROXMOX", False):
        address_fields.append(
            (
                "proxmox_ip",
                "Proxmox IPv4 address",
                host.proxmox_ip,
                "Address of the existing Proxmox host.",
            )
        )
    if host.service_flags.get("ENABLE_TRUENAS", False):
        address_fields.append(
            (
                "truenas_ip",
                "TrueNAS IPv4 address",
                host.truenas_ip,
                "Address of the existing TrueNAS host.",
            )
        )
    if address_fields:
        values = validated_form(
            ui,
            "External service addresses",
            address_fields,
            [
                (key, ipv4, "Invalid IPv4 address: {value}")
                for key, *_ in address_fields
            ],
        )
        for key in values:
            setattr(host, key, values[key])
    if host.service_flags.get("ENABLE_TAILSCALE", False):
        values = validated_form(
            ui,
            "Tailscale",
            [
                (
                    "tailscale_ip",
                    "Existing Tailscale IPv4 address, if any",
                    host.tailscale_ip,
                    "Optional 100.x address; leave blank if this machine has not joined the tailnet yet.",
                )
            ],
            [
                (
                    "tailscale_ip",
                    lambda value: not value or ipv4(value),
                    "Invalid Tailscale IPv4 address: {value}",
                )
            ],
        )
        host.tailscale_ip = values["tailscale_ip"]
        if ui.yes_no(
            "Use this machine as a Tailscale subnet router",
            host.tailscale_routing_mode == "server",
        ):
            host.tailscale_routing_mode = "server"
            route_default = host.tailscale_advertise_route
            if not route_default and len(host.lan_ip.split(".")) == 4:
                route_default = ".".join(host.lan_ip.split(".")[:3]) + ".0/24"
            values = validated_form(
                ui,
                "Tailscale subnet route",
                [
                    (
                        "route",
                        "IPv4 subnet route to advertise",
                        route_default,
                        "CIDR routed through this machine, for example 192.168.1.0/24.",
                    )
                ],
                [("route", ipv4_cidr, "Invalid subnet route: {value}")],
            )
            host.tailscale_advertise_route = values["route"]
        else:
            host.tailscale_routing_mode = "none"
            host.tailscale_advertise_route = ""
    else:
        host.tailscale_routing_mode = "none"
        host.tailscale_advertise_route = ""
    if host.service_flags.get("ENABLE_CIFS", False):
        configure_cifs(host, ui, shares_initialized)
        shares_initialized = True
    if host.service_flags.get("ENABLE_NAS", False):
        if not host.nas.configured:
            if not nas.configure(host, ui):
                host.service_flags["ENABLE_NAS"] = False
        else:
            # Re-enabling NAS after navigating backward should restore the
            # previously reviewed layout without silently dropping it.
            host.nas.enabled = True
    return shares_initialized


def configure_cifs(host: HostConfig, ui: UI, initialized: bool = False) -> None:
    cifs = host.cifs
    cifs.enabled = True
    values = validated_form(
        ui,
        "CIFS server",
        [
            (
                "server",
                "CIFS server IP or hostname",
                cifs.server or host.truenas_ip,
                "Server component used to build the //server/share paths below.",
            )
        ],
        [("server", lambda value: bool(value), "A CIFS server is required: {value}")],
    )
    cifs.server = values["server"]
    if not initialized:
        cifs.media = cifs.appdata = cifs.public = True
        cifs.media_source = f"//{cifs.server}/media"
        cifs.appdata_source = f"//{cifs.server}/appdata"
        cifs.public_source = f"//{cifs.server}/public"
    shares = {"MEDIA": cifs.media, "APPDATA": cifs.appdata, "PUBLIC": cifs.public}
    ui.checklist(
        "Select CIFS shares",
        [
            ("MEDIA", "Media share"),
            ("APPDATA", "Application-data share"),
            ("PUBLIC", "Public share"),
        ],
        shares,
    )
    cifs.media, cifs.appdata, cifs.public = (
        shares["MEDIA"],
        shares["APPDATA"],
        shares["PUBLIC"],
    )
    if not any((cifs.media, cifs.appdata, cifs.public)):
        ui.error("Enable at least one CIFS share.")
        cifs.media = True
    source_fields: list[tuple[str, str, str, str]] = []
    if cifs.media:
        source_fields.append(
            (
                "media_source",
                "Media share source",
                cifs.media_source or f"//{cifs.server}/media",
                "Remote SMB path.",
            )
        )
        source_fields.append(
            (
                "media_mount",
                "Media mount point",
                cifs.media_mount,
                "Absolute mount point for the media CIFS share.",
            )
        )
    if cifs.appdata:
        source_fields.append(
            (
                "appdata_source",
                "Appdata share source",
                cifs.appdata_source or f"//{cifs.server}/appdata",
                "Remote SMB path.",
            )
        )
        source_fields.append(
            (
                "appdata_mount",
                "Appdata mount point",
                cifs.appdata_mount,
                "Absolute mount point for the appdata CIFS share.",
            )
        )
    if cifs.public:
        source_fields.append(
            (
                "public_source",
                "Public share source",
                cifs.public_source or f"//{cifs.server}/public",
                "Remote SMB path.",
            )
        )
        source_fields.append(
            (
                "public_mount",
                "Public mount point",
                cifs.public_mount,
                "Absolute mount point for the public CIFS share.",
            )
        )
    if source_fields:
        values = validated_form(
            ui,
            "CIFS share paths",
            source_fields,
            [
                (
                    key,
                    absolute_path
                    if key.endswith("_mount")
                    else lambda value: bool(value),
                    "Invalid absolute mount path: {value}"
                    if key.endswith("_mount")
                    else "A source is required: {value}",
                )
                for key, *_ in source_fields
            ],
        )
        for key in values:
            setattr(cifs, key, values[key])


def configure_user(host: HostConfig, ui: UI) -> None:
    ui.checklist(
        "Primary-user privileges (Docker daemon access is root-equivalent)",
        [
            (key, label)
            for key, label in [
                ("USER_WHEEL", "sudo/wheel access"),
                ("USER_NETWORKMANAGER", "NetworkManager access"),
                ("USER_DOCKER", "Direct Docker access (root-equivalent)"),
                ("USER_WIRESHARK", "Packet-capture/Wireshark access"),
            ]
        ],
        host.user_groups,
    )


def show_summary(
    host: HostConfig,
    registry: Registry,
    ui: UI,
    *,
    generate_only: bool = False,
    skip_healthcheck: bool = False,
) -> None:
    if generate_only and skip_healthcheck:
        action = "generate without validating or switching"
    elif skip_healthcheck:
        action = "generate and switch without preflight validation"
    elif generate_only:
        action = "generate and validate"
    else:
        action = "generate, validate, and switch"
    if not host.service_flags.get("ENABLE_NGINX", False):
        service_access = "local only (Nginx disabled)"
    elif host.service_access == "lan":
        selectors = []
        if host.lan_interface:
            selectors.append(f"interface {host.lan_interface}")
        if host.lan_source_cidr:
            selectors.append(f"source {host.lan_source_cidr}")
        service_access = f"LAN ({', '.join(selectors)})"
    elif host.service_access == "tailnet":
        service_access = "Tailscale (tailscale0)"
    elif host.service_access == "public":
        service_access = "public/unrestricted"
    else:
        service_access = "local machine only (loopback)"
    lines = [
        "Configuration review",
        "Nothing has been written yet.",
        "",
        f"  Host: {host.host_name}",
        f"  Service preset: {host.service_preset}",
        f"  User: {host.user_name} (UID {host.user_uid}); managed groups and Zsh login shell",
        "  Foundation: NetworkManager enabled; SSH enabled with its firewall port",
        f"  Locale: {host.default_locale}; timezone: {host.time_zone}; console: {host.console_keymap}",
        f"  Repository: {host.repository_path}",
        f"  User files: {host.user_files_directory}",
        f"  LAN address: {host.lan_ip or 'not set'}",
        f"  Service access: {service_access}",
        f"  SSH: port {host.ssh.port}, key mode {host.ssh.key_mode}, password authentication {host.ssh.password_authentication}",
        f"  SSH root login: {host.ssh.root_login}",
        f"  Bootloader: {host.bootloader}",
        f"  GPU mode: {host.gpu_acceleration}",
        f"  Swap: {host.swap_device} ({host.swap_size_mib} MiB)"
        if host.swap_enabled
        else "  Swap: disabled",
    ]
    enabled = [
        service.selection_label
        for service in registry.services
        if host.service_flags.get(service.variable, False)
    ]
    lines.append(f"  Enabled services: {', '.join(enabled) if enabled else 'none'}")
    programs = [
        key.removeprefix("PROGRAM_").replace("_", " ").title()
        for key, enabled in host.program_flags.items()
        if enabled
    ]
    lines.append(f"  Program modules: {', '.join(programs) if programs else 'none'}")
    if host.cifs.enabled:
        lines.append(f"  CIFS server: {host.cifs.server}")
        cifs_shares = [
            ("media", host.cifs.media),
            ("appdata", host.cifs.appdata),
            ("public", host.cifs.public),
        ]
        lines.append(
            f"  CIFS shares: {', '.join(name for name, enabled in cifs_shares if enabled)}"
        )
    if host.nas.enabled:
        lines.append(
            f"  NAS disks: {len(host.nas.data)} data, {len(host.nas.parity)} parity; tank {host.nas.tank_mount}"
        )
    lines += ["", f"The next step will {action} to {host.host_name}."]
    ui.pager("\n".join(lines))


def run_wizard(
    repo_root: Path,
    secrets_dir: Path,
    registry: Registry,
    ui: UI,
    hardware_source: str = "",
    *,
    generate_only: bool = False,
    skip_healthcheck: bool = False,
    standalone: bool = False,
) -> HostConfig:
    host = initial_state(repo_root, secrets_dir)
    host.standalone = standalone
    host.hardware_source = hardware_source
    step = 0
    services_initialized = False
    shares_initialized = False
    while True:
        ui.section_previous_allowed = step > 0
        try:
            if step == 0:
                ui.context = "Step 1 of 7 · Identity"
                configure_identity(host, repo_root, ui, standalone=standalone)
                step = 1
            elif step == 1:
                ui.context = "Step 2 of 7 · Services and programs"
                configure_services(host, registry, ui, services_initialized)
                services_initialized = True
                step = 2
            elif step == 2:
                ui.context = "Step 3 of 7 · Infrastructure and storage"
                configure_infrastructure_selection(host, registry, ui)
                step = 3
            elif step == 3:
                ui.context = "Step 4 of 7 · Locale and network"
                configure_network(host, registry, ui)
                step = 4
            elif step == 4:
                ui.context = "Step 5 of 7 · Hardware"
                configure_hardware(host, ui)
                step = 5
            elif step == 5:
                ui.context = "Step 6 of 7 · Selected service details"
                shares_initialized = configure_selected_details(
                    host, registry, ui, shares_initialized
                )
                step = 6
            elif step == 6:
                ui.context = "Step 7 of 7 · Primary-user privileges"
                configure_user(host, ui)
                step = 7
            else:
                ui.context = "Review"
                show_summary(
                    host,
                    registry,
                    ui,
                    generate_only=generate_only,
                    skip_healthcheck=skip_healthcheck,
                )
                action = ui.review_navigation()
                if action == "apply":
                    break
                if action == "back":
                    step = 6
        except SectionBack:
            if step > 0:
                step -= 1
    ui.context = ""
    ssh.materialize(host, ui)
    return host
