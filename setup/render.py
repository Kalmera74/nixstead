from __future__ import annotations

from .model import HostConfig
from .registry import Registry


PROGRAM_MODULES = {
    "PROGRAM_CORE": "core",
    "PROGRAM_DEVELOPMENT": "development",
    "PROGRAM_HARDWARE": "hardware",
    "PROGRAM_NETWORKING": "networking",
    "PROGRAM_MEDIA": "media",
    "PROGRAM_BACKUP": "backup",
    "PROGRAM_ZSH": "zsh",
    "PROGRAM_YAZI": "yazi",
}


def escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("${", "\\${")


def nullable(value: str) -> str:
    return "null" if not value else f'"{escape(value)}"'


def render_nix_list(values: list[str], indent: str = "        ") -> str:
    if not values:
        return "[ ]"
    return (
        "[\n"
        + "".join(f'{indent}"{escape(value)}"\n' for value in values)
        + indent[:-2]
        + "]"
    )


def render_nas(host: HostConfig) -> str:
    if not host.nas.enabled:
        return ""
    lines = [
        "",
        "  # NAS layout collected by setup. No disks are formatted by setup.",
        "  nixstead.services.nas = {",
        "    enable = true;",
        "    mergerfs.enable = " + ("true" if host.nas.mergerfs else "false") + ";",
        "    snapraid.enable = " + ("true" if host.nas.snapraid else "false") + ";",
        "    # No SMB shares are exported until samba.shares is configured with paths and users.",
        "    samba.enable = " + ("true" if host.nas.samba else "false") + ";",
        f'    tankMount = "{escape(host.nas.tank_mount)}";',
        "    disks = {",
        "      data = [",
    ]
    for disk in host.nas.data:
        lines += [
            "        {",
            f'          name = "{escape(disk.name)}";',
            f'          device = "{escape(disk.device)}";',
            f'          mountPoint = "{escape(disk.mount_point)}";',
            f'          fsType = "{escape(disk.fs_type)}";',
            f"          options = {render_nix_list(disk.options, '            ')};",
            "        }",
        ]
    lines += ["      ];", "      parity = ["]
    for disk in host.nas.parity:
        lines += [
            "        {",
            f'          device = "{escape(disk.device)}";',
            f'          mountPoint = "{escape(disk.mount_point)}";',
            f'          fsType = "{escape(disk.fs_type)}";',
            f"          options = {render_nix_list(disk.options, '            ')};",
            "        }",
        ]
    lines += ["      ];", "    };", "  };"]
    return "\n".join(lines)


def render_cifs(host: HostConfig) -> str:
    if not host.cifs.enabled:
        return ""
    cifs = host.cifs
    lines = ["", "  nixstead.services.cifs = {", "    enable = true;", "    shares = {"]
    for name, enabled, source, mount, options in [
        ("media", cifs.media, cifs.media_source, cifs.media_mount, []),
        (
            "appdata",
            cifs.appdata,
            cifs.appdata_source,
            cifs.appdata_mount,
            ["noperm", "dynperm"],
        ),
        ("public", cifs.public, cifs.public_source, cifs.public_mount, []),
    ]:
        if not enabled:
            lines.append(f"      {name} = null;")
            continue
        lines += [
            f"      {name} = {{",
            f'        source = "{escape(source)}";',
            f'        mountPoint = "{escape(mount)}";',
        ]
        if options:
            lines.append(f"        options = {render_nix_list(options, '          ')};")
        lines.append("      };")
    lines += ["    };", "  };"]
    return "\n".join(lines)


def render_cifs_service_paths(host: HostConfig) -> str:
    if not host.cifs.enabled:
        return ""

    mappings = [
        (
            "ENABLE_QBITTORRENT",
            "media",
            "nixstead.services.arr.qbittorrent.paths.savePath",
            "/data/torrents",
        ),
        (
            "ENABLE_QBITTORRENT",
            "media",
            "nixstead.services.arr.qbittorrent.paths.tempPath",
            "/data/torrents/temp",
        ),
        (
            "ENABLE_TDARR",
            "appdata",
            "nixstead.services.media.tdarr.paths.dataDir",
            "/tdarr",
        ),
        ("ENABLE_TDARR", "media", "nixstead.services.media.tdarr.paths.mediaDir", ""),
        (
            "ENABLE_KIWIX",
            "public",
            "nixstead.services.media.kiwix.paths.dataDir",
            "/kiwix",
        ),
        (
            "ENABLE_IMMICH",
            "media",
            "nixstead.services.media.immich.paths.mediaLocation",
            "/immich",
        ),
        (
            "ENABLE_ROMM",
            "appdata",
            "nixstead.services.media.romm.paths.dataDir",
            "/romm",
        ),
        (
            "ENABLE_ROMM",
            "public",
            "nixstead.services.media.romm.paths.libraryDir",
            "/roms",
        ),
        (
            "ENABLE_TUBEARCHIVIST",
            "appdata",
            "nixstead.services.media.tubearchivist.paths.dataDir",
            "/tubearchivist",
        ),
        (
            "ENABLE_TUBEARCHIVIST",
            "media",
            "nixstead.services.media.tubearchivist.paths.mediaDir",
            "/tubearchivist",
        ),
        (
            "ENABLE_FORGEJO",
            "appdata",
            "nixstead.services.dev.forgejo.paths.repositoryDir",
            "/forgejo/repositories",
        ),
        (
            "ENABLE_SEAFILE",
            "appdata",
            "nixstead.services.productivity.seafile.paths.dataDir",
            "/seafile",
        ),
        (
            "ENABLE_WALLABAG",
            "appdata",
            "nixstead.services.productivity.wallabag.paths.dataDir",
            "/wallabag",
        ),
        (
            "ENABLE_LINKWARDEN",
            "appdata",
            "nixstead.services.productivity.linkwarden.paths.dataDir",
            "/linkwarden",
        ),
        (
            "ENABLE_VAULTWARDEN",
            "appdata",
            "nixstead.services.vaultwarden.paths.backupDir",
            "/vaultwarden-backup",
        ),
    ]
    available_roots = {
        "media": host.cifs.media,
        "appdata": host.cifs.appdata,
        "public": host.cifs.public,
    }
    rendered = [
        f'  {option} = "${{config.nixstead.services.cifs.shares.{root}.mountPoint}}{suffix}";'
        for variable, root, option, suffix in mappings
        if host.service_flags.get(variable, False) and available_roots[root]
    ]
    if not rendered:
        return ""
    return (
        "\n  # Explicit service paths selected for the configured CIFS roots.\n"
        + "\n".join(rendered)
    )


def render_tailscale(host: HostConfig) -> str:
    if not host.service_flags.get("ENABLE_TAILSCALE", False):
        return ""
    routes = (
        [] if not host.tailscale_advertise_route else [host.tailscale_advertise_route]
    )
    return (
        "\n  nixstead.services.tailscale = {\n    enable = true;\n"
        + f'    useRoutingFeatures = "{escape(host.tailscale_routing_mode)}";\n'
        + f"    advertiseRoutes = {render_nix_list(routes, '      ')};\n  }};"
    )


def preset_defaults(registry: Registry, preset: str) -> dict[str, bool]:
    values = {service.variable: False for service in registry.services}
    registry.apply_preset(values, preset)
    return values


def render_service_overrides(host: HostConfig, registry: Registry) -> str:
    defaults = preset_defaults(registry, host.service_preset)
    changed = []
    for service in registry.services:
        if service.variable in {"ENABLE_NAS", "ENABLE_CIFS", "ENABLE_TAILSCALE"}:
            continue
        value = host.service_flags.get(service.variable, False)
        if value != defaults.get(service.variable, False):
            changed.append((service.option_path, value))
    if not changed:
        return ""
    title = (
        "Explicit service choices for this custom host."
        if host.service_preset == "custom"
        else "Service choices that differ from the selected preset."
    )
    return (
        "\n  # "
        + title
        + "\n"
        + "".join(
            f"  {path} = {'true' if value else 'false'};\n" for path, value in changed
        )
    )


def render_service_exposure(host: HostConfig) -> list[str]:
    if not host.service_flags.get("ENABLE_NGINX", False):
        return []

    lines = [
        "      exposure = {",
        f'        services.nginx = "{escape(host.service_access)}";',
    ]
    if host.service_access == "lan":
        lines += [
            "        lan = {",
            f"          interfaces = {render_nix_list([host.lan_interface] if host.lan_interface else [], '            ')};",
            f"          sourceNetworks = {render_nix_list([host.lan_source_cidr] if host.lan_source_cidr else [], '            ')};",
            "        };",
        ]
    elif host.service_access == "tailnet":
        lines += [
            '        tailnet.interfaces = ["tailscale0"];',
        ]
    lines.append("      };")
    return lines


def render_service_inputs(host: HostConfig, registry: Registry) -> str:
    lines = []
    for service in registry.services:
        if not host.service_flags.get(service.variable, False):
            continue
        for item in service.inputs:
            path = "nixstead.services." + ".".join(item["optionPath"])
            if path not in host.service_settings:
                raise ValueError(
                    f"{service.label} requires an explicit value for {path}"
                )
            value = host.service_settings[path]
            lines.append(f'  {path} = "{escape(value)}";')
    return "\n".join(lines)


def render_consumer_flake(host: HostConfig, nixstead_url: str) -> str:
    modules = ["        nixstead.nixosModules.default"]
    modules += [
        f"        nixstead.nixosModules.program-{name}"
        for variable, name in PROGRAM_MODULES.items()
        if host.program_flags.get(variable, False)
    ]
    modules.append("        ./configuration.nix")
    return "\n".join(
        [
            "{",
            '  description = "NixOS homelab generated by Nixstead";',
            "",
            "  inputs = {",
            '    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";',
            "    nixstead = {",
            f'      url = "{escape(nixstead_url)}";',
            '      inputs.nixpkgs.follows = "nixpkgs";',
            "    };",
            "  };",
            "",
            "  outputs = { nixpkgs, nixstead, ... }: {",
            f'    nixosConfigurations."{escape(host.host_name)}" = nixpkgs.lib.nixosSystem {{',
            "      modules = [",
            *modules,
            "      ];",
            "    };",
            "  };",
            "}",
            "",
        ]
    )


def render_host(
    host: HostConfig, registry: Registry, *, standalone: bool = False
) -> str:
    preset = "none" if host.service_preset == "custom" else host.service_preset
    imports = ["    ./hardware-configuration.nix"]
    if not standalone:
        imports += [
            f"    ../../modules/programs/{name}.nix"
            for variable, name in PROGRAM_MODULES.items()
            if host.program_flags.get(variable, False)
        ]
    lines = [
        "{",
        "  config,",
        "  ...",
        "}: {",
        "  imports = [",
        *imports,
        "  ];",
        "",
        f'  system.stateVersion = "{escape(host.system_state_version)}";',
        f'  nixstead.preset = "{preset}";',
        "  nixstead.tools.enable = true;",
        "",
        "  nixstead.containerImages.overrides =",
        "    if builtins.pathExists ./container-images.nix",
        "    then import ./container-images.nix",
        "    else {};",
    ]
    if any(
        service.secrets and host.service_flags.get(service.variable, False)
        for service in registry.services
    ):
        lines += ["", "  nixstead.secrets = {", "    enable = true;"]
        if standalone and host.secrets_dir == host.repo_root / "secrets":
            lines.append(f"    sopsFile = ./secrets/{escape(host.host_name)}.yaml;")
        lines.append("  };")
    lines += [
        "",
        "  nixstead.host = {",
        f'    hostName = "{escape(host.host_name)}";',
        f'    configurationName = "{escape(host.host_name)}";',
        f'    repositoryPath = "{escape(host.repository_path)}";',
        '    groups.media = "media";',
        f"    ports.ssh = {host.ssh.port};",
        "    ssh = {",
        "      authorizedKeys = [",
    ]
    if host.ssh.authorized_key:
        lines.append(f'        "{escape(host.ssh.authorized_key)}"')
    lines += [
        "      ];",
        f"      passwordAuthentication = {'true' if host.ssh.password_authentication else 'false'};",
        f'      rootLogin = "{escape(host.ssh.root_login)}";',
        "    };",
        "    network = {",
        f"      lan = {nullable(host.lan_ip)};",
        f"      tailscale = {nullable(host.tailscale_ip)};",
        f"      router = {nullable(host.router_ip)};",
        f"      switch = {nullable(host.switch_ip) if host.use_managed_switch else 'null'};",
        f"      pihole = {nullable(host.pihole_ip)};",
        f"      proxmox = {nullable(host.proxmox_ip)};",
        f"      truenas = {nullable(host.truenas_ip)};",
        *render_service_exposure(host),
        "    };",
        "    hardware = {",
        f"      audio.enable = {'true' if host.audio else 'false'};",
        f"      bluetooth.enable = {'true' if host.bluetooth else 'false'};",
        f"      enableAllFirmware = {'true' if host.all_firmware else 'false'};",
        f'      gpu.acceleration = "{escape(host.gpu_acceleration)}";',
        "      swap = {",
        f"        enable = {'true' if host.swap_enabled else 'false'};",
        f'        device = "{escape(host.swap_device)}";',
        f"        sizeMiB = {host.swap_size_mib};",
        "      };",
        "    };",
        "    locale = {",
        f'      timeZone = "{escape(host.time_zone)}";',
        f'      defaultLocale = "{escape(host.default_locale)}";',
        f'      consoleKeyMap = "{escape(host.console_keymap)}";',
        "    };",
        "    user = {",
        "      enable = true;",
        f'      name = "{escape(host.user_name)}";',
        f'      description = "{escape(host.user_description)}";',
        f"      uid = {host.user_uid};",
        f'      generatedFilesDirectory = "{escape(host.user_generated_files_directory)}";',
        "      extraGroups = [",
    ]
    groups = {
        "USER_NETWORKMANAGER": "networkmanager",
        "USER_WHEEL": "wheel",
        "USER_DOCKER": "docker",
        "USER_WIRESHARK": "wireshark",
    }
    lines += [
        f'        "{group}"'
        for variable, group in groups.items()
        if host.user_groups.get(variable, False)
    ]
    lines += [
        "      ];",
        "    };",
        "  };",
        render_cifs(host),
        render_cifs_service_paths(host),
        render_tailscale(host),
        render_nas(host),
        render_service_overrides(host, registry),
        render_service_inputs(host, registry),
    ]
    if host.bootloader == "systemd-boot":
        lines += [
            "",
            "  boot.loader.systemd-boot.enable = true;",
            "  boot.loader.efi.canTouchEfiVariables = true;",
        ]
    elif host.bootloader == "grub":
        lines += [
            "",
            "  boot.loader.grub = {",
            "    enable = true;",
            f'    device = "{escape(host.grub_device)}";',
            f"    useOSProber = {'true' if host.grub_use_os_prober else 'false'};",
            "  };",
        ]
    else:
        lines += [
            "",
            "  boot.loader.grub.enable = false;",
            "  boot.loader.systemd-boot.enable = false;",
        ]
    lines += ["}"]
    return "\n".join(line for line in lines if line is not None)
