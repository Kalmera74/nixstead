from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List


@dataclass
class NasDisk:
    name: str
    device: str
    mount_point: str
    fs_type: str
    options: List[str] = field(default_factory=lambda: ["nofail"])


@dataclass
class NasParityDisk:
    device: str
    mount_point: str
    fs_type: str
    options: List[str] = field(default_factory=lambda: ["nofail"])


@dataclass
class NasConfig:
    enabled: bool = False
    configured: bool = False
    mergerfs: bool = True
    snapraid: bool = True
    samba: bool = True
    tank_mount: str = "/mnt/tank"
    data: List[NasDisk] = field(default_factory=list)
    parity: List[NasParityDisk] = field(default_factory=list)


@dataclass
class SshConfig:
    port: int = 22
    key_mode: str = ""
    authorized_key: str = ""
    private_key_path: str = ""
    password_authentication: bool = False
    root_login: str = "no"


@dataclass
class CifsConfig:
    enabled: bool = False
    server: str = ""
    media: bool = False
    appdata: bool = False
    public: bool = False
    media_source: str = ""
    appdata_source: str = ""
    public_source: str = ""
    media_mount: str = "/mnt/media"
    appdata_mount: str = "/mnt/appdata"
    public_mount: str = "/mnt/public"


@dataclass
class HostConfig:
    repo_root: Path
    secrets_dir: Path
    host_name: str = ""
    user_name: str = ""
    user_description: str = ""
    user_uid: int = 1000
    repository_path: str = ""
    system_state_version: str = ""
    service_preset: str = "custom"
    service_flags: Dict[str, bool] = field(default_factory=dict)
    service_settings: Dict[str, object] = field(default_factory=dict)
    program_flags: Dict[str, bool] = field(default_factory=dict)
    user_generated_files_directory: str = ".local/share/nixstead"
    user_files_directory: Path = Path()
    user_sops_age_key_file: Path = Path()
    user_groups: Dict[str, bool] = field(default_factory=dict)
    ssh: SshConfig = field(default_factory=SshConfig)
    nas: NasConfig = field(default_factory=NasConfig)
    cifs: CifsConfig = field(default_factory=CifsConfig)
    lan_ip: str = ""
    router_ip: str = ""
    switch_ip: str = ""
    use_managed_switch: bool = False
    pihole_ip: str = ""
    proxmox_ip: str = ""
    truenas_ip: str = ""
    tailscale_ip: str = ""
    tailscale_routing_mode: str = "none"
    tailscale_advertise_route: str = ""
    service_access: str = "loopback"
    lan_interface: str = ""
    lan_source_cidr: str = ""
    time_zone: str = "UTC"
    default_locale: str = "en_US.UTF-8"
    console_keymap: str = "us"
    bootloader: str = "none"
    grub_device: str = ""
    grub_use_os_prober: bool = False
    audio: bool = False
    bluetooth: bool = False
    all_firmware: bool = True
    gpu_acceleration: str = "none"
    swap_enabled: bool = False
    swap_device: str = "/swapfile"
    swap_size_mib: int = 0
    hardware_source: str = ""
    user_existed_before: bool = True
    created_user: str = ""
    host_directory: Path = Path()
    new_host_directory: Path = Path()
    target_name: str = ""
    standalone: bool = False

    def sync_user_paths(self) -> None:
        import pwd

        try:
            home = Path(pwd.getpwnam(self.user_name).pw_dir)
        except KeyError:
            home = Path("/home") / self.user_name
        self.user_files_directory = home / self.user_generated_files_directory
        self.user_sops_age_key_file = self.user_files_directory / "sops-age-key.txt"
