# Configuring a host

A host file contains facts and choices specific to one machine. The root flake
already imports `nixosModules.default`, so repository hosts should import only
their hardware configuration and optional program groups.

## Minimal repository host

```nix
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/programs/core.nix
    ../../modules/programs/zsh.nix
  ];

  # New 26.05 installation; preserve the original value on existing systems.
  system.stateVersion = "26.05";
  nixstead.preset = "minimal";

  nixstead.host = {
    hostName = "homelab";
    repositoryPath = "/etc/nixos-config";
    network.lan = "192.168.1.20";

    user = {
      enable = true;
      name = "admin";
      description = "Homelab administrator";
      uid = 1000;
      extraGroups = ["networkmanager" "wheel"];
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
```

The flake assigns `nixstead.host.configurationName` from the directory name. It may be
set explicitly in consumer flakes or generated hosts.

## Complete annotated host example

The following is a menu of the main host-level options. It is intentionally
commented and selective: enabling a parent stack does not mean every child must
remain enabled, and storage paths are only moved when the host explicitly sets
them. Copy the pieces that apply to the machine instead of enabling everything
at once.

```nix
{config, lib, pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix

    # Independent command-line program groups.
    ../../modules/programs/core.nix
    ../../modules/programs/networking.nix
    ../../modules/programs/media.nix
    ../../modules/programs/backup.nix
    ../../modules/programs/zsh.nix
  ];

  # Use the installed system's original value when migrating an existing host.
  # A new installation should use the release value documented by the template.
  system.stateVersion = "26.05";

  # none, minimal, media-server, development, full, or custom.
  # full is advanced/demo; use a smaller preset for a first host.
  nixstead.preset = "media-server";

  # Public-foundation policy is opt-in.
  nixstead.system = {
    allowUnfree = true;
    autoOptimiseStore = true;
    cleanTmpOnBoot = true;
    zram = true;
    garbageCollection = {
      enable = true;
      dates = "weekly";
      deleteOlderThan = "30d";
    };
  };

  nixstead.host = {
    hostName = "media-host";
    configurationName = "media-host";
    repositoryPath = "/etc/nixos-config";
    groups = {
      media = "media";
      mediaGid = 1001;
    };

    network = {
      # Registry service defaults become, for example, radarr.home.arpa.
      baseDomain = "home.arpa";
      lan = "192.168.1.20";
      tailscale = "100.64.0.20";
      router = "192.168.1.1";
      pihole = "192.168.1.53";
      proxmox = "192.168.1.10";
      truenas = "192.168.1.30";
      exposure = {
        # loopback, lan, tailnet, or public
        default = "loopback";
        services.jellyfin = "lan";
        services.homepage = "lan";
        lan.interfaces = ["enp1s0"];
        lan.sourceNetworks = ["192.168.1.0/24"];
        tailnet.interfaces = ["tailscale0"];
      };
    };

    ports = {
      ssh = 2222;
      http = 80;
      https = 443;
    };

    ssh = {
      authorizedKeys = ["ssh-ed25519 AAAA... admin@example"];
      passwordAuthentication = false;
      rootLogin = "no";
    };

    locale = {
      timeZone = "Europe/Istanbul";
      defaultLocale = "en_US.UTF-8";
      consoleKeyMap = "trq";
      extraLocaleSettings.LC_TIME = "tr_TR.UTF-8";
    };

    user = {
      enable = true;
      name = "admin";
      description = "Homelab administrator";
      uid = 1000;
      generatedFilesDirectory = ".local/share/nixstead";
      extraGroups = ["networkmanager" "wheel"];
    };

    hardware = {
      audio.enable = true;
      bluetooth.enable = true;
      enableAllFirmware = true;
      gpu.acceleration = "cuda"; # none, cuda, or rocm
      swap = {
        enable = true;
        device = "/swapfile";
        sizeMiB = 16 * 1024;
      };
    };
  };

  # Required when enabled services use encrypted credentials.
  nixstead.secrets = {
    enable = true;
    sopsFile = ./secrets/media-host.yaml;
    age = {
      sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
      keyFile = "/var/lib/sops-nix/key.txt";
    };
  };

  nixstead.backups = {
    enable = true;
    repository = "ssh://backup@example.net/./borg/media-host";
    environmentFile = "/run/secrets/nixstead-backup-env";
    scope = "full"; # config keeps the legacy exclusion-oriented scope
    schedule = "daily";
    verifySchedule = "weekly";
  };

  nixstead.services = {
    # Dashboard and host-specific shortcuts.
    homepage = {
      enable = true;
      domain = "home.home.arpa";
      port = 2525;
      shortcuts = [
        {
          name = "GitHub";
          icon = "github.png";
          description = "Source code";
          href = "https://github.com/";
        }
      ];
    };

    arr = {
      enable = true;
      sonarr.enable = true;
      radarr.enable = true;
      prowlarr.enable = true;
      qbittorrent = {
        enable = true;
        domain = "bit.home.arpa";
        paths = {
          savePath = "${config.nixstead.services.cifs.shares.media.mountPoint}/data/torrents";
          tempPath = "${config.nixstead.services.cifs.shares.media.mountPoint}/data/torrents/temp";
        };
      };
      # sonarr, radarr, lidarr, readarr, bazarr, prowlarr,
      # qbittorrent, and swaparr are independently toggleable.
    };

    media = {
      enable = true;
      jellyfin.enable = true;
      seerr.enable = true;
      tdarr = {
        enable = true;
        server = true;
        node = true;
        serverPort = 8266;
        paths.mediaDir = config.nixstead.services.cifs.shares.media.mountPoint;
      };
      immich = {
        enable = true;
        paths.mediaLocation = "${config.nixstead.services.cifs.shares.media.mountPoint}/immich";
      };
      romm = {
        enable = true;
        paths = {
          dataDir = "${config.nixstead.services.cifs.shares.appdata.mountPoint}/romm";
          libraryDir = "${config.nixstead.services.cifs.shares.public.mountPoint}/roms";
        };
      };
      # komga, kavita, audiobookshelf, kiwix, and tubearchivist are also
      # independent children of the media stack.
    };

    dev = {
      enable = true;
      grafana.enable = true;
      prometheus.enable = true;
      loki.enable = true;
      postgresql.enable = true;
      forgejo = {
        enable = true;
        paths.repositoryDir = "${config.nixstead.services.cifs.shares.appdata.mountPoint}/forgejo/repositories";
      };
      # redis, rabbitmq, mongodb, gitea, pgadmin, seaweedfs, uptimekuma, and
      # ntfy are independently toggleable as well.
    };

    localai = {
      enable = true;
      ollama.enable = true;
      openwebui = {
        enable = true;
        ollamaUrl = "http://127.0.0.1:11434";
      };
    };

    productivity = {
      enable = true;
      paperless = {
        enable = true;
        paths.dataDir = "${config.nixstead.services.cifs.shares.media.mountPoint}/paperless";
      };
      nextcloud.enable = true;
      n8n.enable = true;
      stirlingpdf.enable = true;
      seafile.enable = true;
      wallabag.enable = true;
      linkwarden.enable = true;
      snapotter = {
        enable = true;
        auth.enable = true;
      };
      mealie.enable = true;
      actualbudget.enable = true;
      miniflux.enable = true;
      searxng.enable = true;
    };

    vaultwarden = {
      enable = true;
      paths.backupDir = "${config.nixstead.services.cifs.shares.appdata.mountPoint}/vaultwarden-backup";
    };

    homeassistant = {
      enable = true;
      paths.dataDir = "/var/lib/hass";
    };

    syncthing.enable = true;
    scrutiny.enable = true;

    tailscale = {
      enable = true;
      useRoutingFeatures = "server"; # none, client, server, or both
      advertiseRoutes = ["192.168.1.0/24"];
    };

    # CIFS share names are arbitrary. There are no mandatory media/appdata/
    # public/downloads roles; services reference whichever shares you define.
    cifs = {
      enable = true;
      credentialsFile = "/run/secrets/cifs-credentials";
      # uid, gid, and mountOptions have safe defaults; override them when the
      # NAS requires a different account or SMB version.
      # uid = 1000;
      # gid = "media";
      # mountOptions = ["credentials=/run/secrets/cifs-credentials" "vers=3.0"];
      shares = {
        media = {
          source = "//192.168.1.30/media";
          mountPoint = "/mnt/media";
        };
        appdata = {
          source = "//192.168.1.30/appdata";
          mountPoint = "/mnt/appdata";
          options = ["noperm" "dynperm"];
        };
        public = {
          source = "//192.168.1.30/public";
          mountPoint = "/mnt/public";
        };
      };
    };

    # External systems are integrations, not locally installed products.
    pihole.enable = true;
    proxmox.enable = true;
    truenas.enable = true;
  };
}
```

The example covers the normal configuration surface. The complete service
catalog, registry IDs, ports, domains, presets, path options, and child names
are listed in [Services](services.md). The public module exports and release
compatibility boundary are described in [Module API](module-api.md).

## Optional NAS and TLS configuration

The CIFS stack mounts shares exported by another machine. If this host owns
the disks instead, the NAS stack declares each block device and can optionally
enable mergerfs, SnapRAID, and Samba. Data disks are required; parity disks are
required when SnapRAID is enabled:

```nix
nixstead.services.nas = {
  enable = true;
  tankMount = "/srv/nas";
  mergerfs.enable = true;
  snapraid.enable = true;
  samba.enable = true;
  disks = {
    data = [
      {
        name = "data1";
        device = "/dev/disk/by-uuid/1111-2222";
        mountPoint = "/srv/disk1";
        fsType = "xfs";
        options = ["nofail"];
      }
    ];
    parity = [
      {
        device = "/dev/disk/by-uuid/3333-4444";
        mountPoint = "/srv/parity1";
        fsType = "xfs";
        options = ["nofail"];
      }
    ];
  };
};
```

Nginx is enabled by the selected proxy-enabled services. Its generated local
CA is normally enough for a homelab; an existing CA can be supplied as paired
runtime files (keep the private key in SOPS or another protected secret):

```nix
nixstead.services.nginx = {
  enable = true;
  ca = {
    certificateFile = "/etc/nixstead-ca/root-ca.crt";
    privateKeyFile = "/run/secrets/nixstead-ca-key";
    homeCertificateFile = "/home/admin/.local/share/nixstead/media-host-nginx-ca.crt";
    renewBeforeDays = 30;
  };
};
```

Only enabled registry services receive proxy domains and certificates. A
service can therefore be disabled without leaving an unrelated certificate or
virtual host behind.

## Optional host policy

The reusable foundation enables flakes but leaves opinionated maintenance and
memory policy disabled. A host can opt in explicitly:

```nix
nixstead.system = {
  allowUnfree = true;
  autoOptimiseStore = true;
  cleanTmpOnBoot = true;
  zram = true;
  garbageCollection = {
    enable = true;
    dates = "weekly";
    deleteOlderThan = "30d";
  };
};
```

The service catalog has a narrow allowlist for unfree packages required by
enabled service modules; it does not grant global unfree-package access.
Python and Go are installed only through the optional development program
module, never by importing the development service catalog.

## CIFS mount references

`nixstead.services.cifs.shares` is an arbitrary attribute set: users choose the share
names and declare each source and mount point once. There are no mandatory
media, appdata, public, or downloads paths. Service defaults remain native or
service-local until the host explicitly references a share's `mountPoint`.

```nix
nixstead.services.cifs = {
  enable = true;
  shares.media = {
    source = "//192.168.1.30/media";
    mountPoint = "/mnt/media";
  };
};

nixstead.services.arr.qbittorrent.paths = {
  savePath = "${config.nixstead.services.cifs.shares.media.mountPoint}/data/torrents";
  tempPath = "${config.nixstead.services.cifs.shares.media.mountPoint}/data/torrents/temp";
};

nixstead.services.media.immich.paths.mediaLocation =
  "${config.nixstead.services.cifs.shares.media.mountPoint}/immich";
```

## Packaged command options

| Option | Default | Meaning |
| --- | --- | --- |
| `nixstead.tools.enable` | `false` | Install the grouped `nixstead` administration command on the system `PATH` |
| `nixstead.tools.media.enable` | `false` | Add optional media/library subcommands and their heavier runtime dependencies |

The installed command uses `nixstead.host.repositoryPath` as its default mutable flake
and `nixstead.host.configurationName` as their default target. Either can be
overridden for one invocation with `NIXSTEAD_REPOSITORY_ROOT` or
`NIXSTEAD_HOST`.

## `nixstead.host` reference

### Identity

| Option | Default | Meaning |
| --- | --- | --- |
| `nixstead.host.hostName` | `"nixos"` | System network hostname |
| `nixstead.host.configurationName` | `"nixos"` | Flake target used by rebuild aliases |
| `nixstead.host.repositoryPath` | `"/etc/nixos"` | On-machine path used by rebuild aliases and manually invoked repository tools |
| `nixstead.host.groups.media` | `"media"` | Shared media-access group |

### Network addresses

The nullable `nixstead.host.network` fields are:

- `lan`
- `tailscale`
- `router`
- `switch`
- `pihole`
- `proxmox`
- `truenas`

External integrations use their corresponding address. Locally hosted services
default to loopback exposure; where the application supports a configurable
listener, it binds to `127.0.0.1`. Leaving an unused address as `null` is
preferred to inventing a placeholder.

Network exposure is configured under `nixstead.host.network.exposure`. Registry
entries default to `"loopback"`; `exposure.default` can override that policy for
the entire host, while per-service overrides accept `"loopback"`, `"lan"`,
`"tailnet"`, or `"public"`. See [Networking](networking.md) for interface and
source-network selectors.

Host ports default to SSH `22`, HTTP `80`, and HTTPS `443`:

```nix
nixstead.host.ports = {
  ssh = 2222;
  http = 80;
  https = 443;
};
```

SSH access for the managed user is configured separately:

```nix
nixstead.host.ssh = {
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... admin@example"
  ];
  passwordAuthentication = false;
  rootLogin = "no";
};
```

`passwordAuthentication` controls both password and keyboard-interactive SSH
authentication. `rootLogin` accepts the OpenSSH `PermitRootLogin` policies and
defaults to `"no"`. The SSH port is passed to sshd as well as the firewall, so
changing `nixstead.host.ports.ssh` keeps the listener and firewall rule aligned.
`authorizedKeys` defaults to an empty list, so password-only access is supported:

```nix
nixstead.host.ssh = {
  authorizedKeys = [];
  passwordAuthentication = true;
};
```

### Locale

```nix
nixstead.host.locale = {
  timeZone = "Europe/Istanbul";
  defaultLocale = "en_US.UTF-8";
  consoleKeyMap = "trq";
  extraLocaleSettings.LC_TIME = "tr_TR.UTF-8";
};
```

Defaults are UTC, `en_US.UTF-8`, and the `us` console keymap.

### User

```nix
nixstead.host.user = {
  enable = true;
  name = "admin";
  description = "Administrator";
  uid = 1000;
  generatedFilesDirectory = ".local/share/nixstead";
  extraGroups = ["networkmanager" "wheel" "docker"];
};
```

The shared media group is added automatically. Only grant privileged groups
when the user needs them. In particular, [Docker documents that membership in
the `docker` group grants root-level privileges](https://docs.docker.com/engine/install/linux-postinstall/);
container services do not require the interactive user to belong to that group.

`generatedFilesDirectory` is relative to the managed user's home. Its default
collects user-owned Nixstead artifacts in `~/.local/share/nixstead`, including
wizard-generated SSH keys, the admin SOPS age identity, and the public Nginx CA
certificate. Runtime service secrets and system-owned host/signing keys remain
in their protected system locations.

### Optional hardware

```nix
nixstead.host.hardware = {
  audio.enable = true;
  bluetooth.enable = true;
  enableAllFirmware = true;
  gpu.acceleration = "cuda"; # none, cuda, or rocm

  swap = {
    enable = true;
    device = "/swapfile";
    sizeMiB = 16 * 1024;
  };
};
```

Optional hardware defaults to off. The module asserts that enabled swap has a
non-zero size.

## Program groups

Programs are deliberately independent from service presets. Import only the
sets needed by the host:

```nix
imports = [
  ../../modules/programs/core.nix
  ../../modules/programs/development.nix
  ../../modules/programs/hardware.nix
  ../../modules/programs/networking.nix
  ../../modules/programs/media.nix
  ../../modules/programs/backup.nix
  ../../modules/programs/zsh.nix
  ../../modules/programs/yazi.nix
];
```

See `modules/programs/README.md` for the package intent of each group.

## Service option shape

Most ordinary services expose:

```nix
nixstead.services.<path> = {
  enable = true;
  domain = "service.home.arpa";
  ip = "192.168.1.20";
  port = 1234;
};
```

Not every field is meaningful for every service. Services that support storage
overrides add a typed `paths` submodule under their own `nixstead.services` option;
the implementation maps it to native NixOS or container settings. Extensions
such as Tdarr's `server`, `node`, and `serverPort`, SeaweedFS's `masterPort`,
and CIFS/NAS storage settings are defined by their own stack modules.

## Parent stacks

These groups provide an `.enable` switch:

- `nixstead.services.arr.enable`
- `nixstead.services.media.enable`
- `nixstead.services.dev.enable`
- `nixstead.services.localai.enable`
- `nixstead.services.productivity.enable`
- `nixstead.services.nas.enable`

Enabling a parent applies default-on values to its children. A child can still
be disabled explicitly:

```nix
nixstead.services.arr = {
  enable = true;
  lidarr.enable = false;
  readarr.enable = false;
};
```

For carefully curated selections, use `nixstead.preset` or enable children directly.

## Worked media host

```nix
{config, ...}: {
  nixstead.preset = "media-server";

  nixstead.host.network = {
    lan = "192.168.1.20";
    truenas = "192.168.1.30";
  };

  nixstead.services = {
    arr.lidarr.enable = false;
    media = {
      seerr.enable = true;
      tdarr.node = true;
    };

    cifs = {
      enable = true;
      shares = {
        media = {
          source = "//192.168.1.30/media";
          mountPoint = "/mnt/media";
        };
        appdata = {
          source = "//192.168.1.30/appdata";
          mountPoint = "/mnt/appdata";
          options = ["noperm" "dynperm"];
        };
        public = {
          source = "//192.168.1.30/public";
          mountPoint = "/mnt/public";
        };
      };
    };

    arr.qbittorrent.paths.savePath =
      "${config.nixstead.services.cifs.shares.media.mountPoint}/data/torrents";
  };
}
```

## Worked development host

```nix
{
  nixstead.preset = "development";

  # Forgejo is selected by the preset; Gitea remains an explicit alternative.
  nixstead.services.dev = {
    forgejo.enable = false;
    gitea.enable = true;
    mongodb.enable = false;
  };
}
```

## External integrations

Pi-hole, Proxmox, and TrueNAS are modeled as services because they participate
in Nginx, Homepage, and DNS integration, but this host does not install those
external systems:

```nix
nixstead.host.network = {
  pihole = "192.168.1.53";
  proxmox = "192.168.1.10";
  truenas = "192.168.1.30";
};

nixstead.services = {
  pihole.enable = true;
  proxmox.enable = true;
  truenas.enable = true;
};
```

## Inspecting resolved configuration

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.host

nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.services

nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.serviceRegistry
```

Encrypted repository host files support pure evaluation. Set
`NIXSTEAD_SECRETS_DIR` and use `--impure` only to override them with another
encrypted directory; plaintext values are never evaluated.
