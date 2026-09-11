{
  pkgs,
  publicModules,
}: let
  secretFixture = import ../../lib/secret-fixture.nix {
    inherit pkgs;
    generator = ./credentials.py;
  };
  base = {
    imports = [secretFixture];
    system.stateVersion = "26.05";
    environment.etc."cifs-credentials-fixture.py".source = ./credentials.py;
    virtualisation.memorySize = 768;
    virtualisation.diskSize = 4096;
  };
  clientSettings = {
    imports = [publicModules.cifs];
    users.groups.fixture.gid = 2350;
    users.users.fixture-client = {
      isSystemUser = true;
      uid = 2350;
      group = "fixture";
    };
    nixstead.services.cifs = {
      enable = true;
      uid = 2350;
      gid = "fixture";
      shares = {
        writable = {
          source = "//server/writable";
          mountPoint = "/mnt/rw";
          options = ["cache=none" "soft" "echo_interval=1" "x-systemd.mount-timeout=5s"];
        };
        readonly = {
          source = "//server/readonly";
          mountPoint = "/mnt/readonly";
          options = ["ro" "cache=none" "soft" "echo_interval=1" "x-systemd.mount-timeout=5s"];
        };
      };
    };
  };
  nativeClient = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    inherit pkgs;
    system = pkgs.stdenv.hostPlatform.system;
    modules = [clientSettings];
  };
in {
  client = {
    imports = [clientSettings base];
    # QEMU replaces ordinary fileSystems. Preserve mount definitions obtained
    # from the actual public module in a small evaluation without the VM module;
    # the VM retains its generated root/store/shared filesystem declarations.
    virtualisation.fileSystems = nativeClient.config.fileSystems;
  };
  server = {
    imports = [publicModules.nas base];
    sops.secrets = {
      "cifs/username" = {};
      "cifs/password" = {};
      "cifs/domain" = {};
    };
    users.users.fixture-smb = {
      isSystemUser = true;
      uid = 3344;
      group = "users";
    };
    nixstead.services.nas.samba = {
      enable = true;
      shares = {
        writable = {
          path = "/srv/cifs-peer-writable";
          users = ["fixture-smb"];
          readOnly = false;
        };
        readonly = {
          path = "/srv/cifs-peer-readonly";
          users = ["fixture-smb"];
          readOnly = true;
        };
      };
    };
    nixstead.host.network.exposure.services.samba = "public";
    environment.systemPackages = [pkgs.samba];
    systemd.tmpfiles.rules = ["d /srv/cifs-peer-writable 0700 fixture-smb users -" "d /srv/cifs-peer-readonly 0700 fixture-smb users -"];
    systemd.services.cifs-fixture-account = {
      path = [pkgs.samba];
      before = ["samba-smbd.service"];
      requiredBy = ["samba-smbd.service"];
      after = ["sops-install-secrets.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.python3}/bin/python3 /etc/cifs-credentials-fixture.py install-user";
      };
    };
  };
}
