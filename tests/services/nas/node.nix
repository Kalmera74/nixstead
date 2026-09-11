{
  pkgs,
  publicModules,
}: let
  settings = {
    imports = [publicModules.nas];
    nixstead.services.nas = {
      enable = true;
      samba.enable = false;
      tankMount = "/srv/pool";
      disks = {
        data = [
          {
            name = "data1";
            device = "/dev/vdb";
            mountPoint = "/mnt/data1";
            fsType = "ext4";
          }
          {
            name = "data2";
            device = "/dev/vdc";
            mountPoint = "/mnt/data2";
            fsType = "ext4";
          }
        ];
        parity = [
          {
            device = "/dev/vdd";
            mountPoint = "/mnt/parity";
            fsType = "ext4";
          }
        ];
      };
    };
  };
  native = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    inherit pkgs;
    system = pkgs.stdenv.hostPlatform.system;
    modules = [settings];
  };
in
  {lib, ...}: {
    imports = [settings];
    system.stateVersion = "26.05";
    virtualisation = {
      memorySize = 768;
      diskSize = 4096;
      # Sparse images retain mergerfs's native minimum-free-space policy while
      # the fixture writes only a few MiB of actual data.
      emptyDiskImages = [8192 8192 12288];
      # Test-only autoFormat applies solely to the disposable, initially blank
      # VM disks. Mount definitions otherwise come from the real public module.
      fileSystems = lib.mapAttrs (_: mount:
        mount // lib.optionalAttrs (mount.fsType == "ext4") {autoFormat = true;})
      native.config.fileSystems;
    };
    services.snapraid.scrub = {
      plan = 100;
      olderThan = 0;
    };
    systemd.timers.snapraid-sync.wantedBy = lib.mkForce [];
    systemd.timers.snapraid-scrub.wantedBy = lib.mkForce [];
    environment.systemPackages = [pkgs.python3];
    environment.etc."nas-fixture-probe.py".source = ./probe.py;
    # Represent a service consumer honoring the storage owner's mount boundary.
    systemd.services.nas-fixture-writer = {
      unitConfig.RequiresMountsFor = ["/srv/pool"];
      serviceConfig.Type = "oneshot";
      script = ''printf 'Managed consumer bytes\n' > /srv/pool/consumer.txt'';
    };
  }
