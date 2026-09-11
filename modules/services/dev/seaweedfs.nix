{
  config,
  host,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev;
  dataDir = cfg.seaweedfs.paths.dataDir;
  dataPaths = {
    masterDir = "${dataDir}/master";
    volumeDir = "${dataDir}/volume";
    filerDir = "${dataDir}/filer";
  };
in {
  config = lib.mkIf cfg.seaweedfs.enable {
    assertions = [
      {
        assertion = cfg.seaweedfs.port != cfg.seaweedfs.masterPort;
        message = "nixstead.services.dev.seaweedfs.port and masterPort must be different.";
      }
    ];

    # The pinned server command selects filer storage through filer.toml;
    # -filer.dir is not supported by SeaweedFS 4.x.
    environment.etc."seaweedfs/filer.toml".text = ''
      [leveldb2]
      enabled = true
      dir = ${builtins.toJSON dataPaths.filerDir}
    '';

    system.activationScripts.seaweedfs-data-dirs = {
      deps = [
        "users"
        "groups"
      ];
      text = ''
        install -d -m 0755 -o root -g root ${lib.escapeShellArg dataPaths.masterDir}
        install -d -m 0755 -o root -g root ${lib.escapeShellArg dataPaths.volumeDir}
        install -d -m 0755 -o root -g root ${lib.escapeShellArg dataPaths.filerDir}
      '';
    };

    systemd.services.seaweedfs = {
      description = "SeaweedFS server";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      unitConfig.RequiresMountsFor = [dataDir];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;
        ExecStart = ''
          ${lib.getExe pkgs.seaweedfs} -config_dir=/etc/seaweedfs server \
            -ip=127.0.0.1 \
            -ip.bind=${serviceBindAddress "seaweedfs"} \
            -master.port=${toString cfg.seaweedfs.masterPort} \
            -filer=true \
            -filer.port=${toString config.nixstead.services.dev.seaweedfs.port} \
            -master.dir=${dataPaths.masterDir} \
            -dir=${dataPaths.volumeDir}
        '';
      };
    };
  };
}
