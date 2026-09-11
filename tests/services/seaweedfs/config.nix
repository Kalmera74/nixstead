{
  lib,
  mkSystem,
  serviceContract,
  ...
}: let
  port = 23456;
  cfg =
    (mkSystem [
      {
        nixstead.services.dev.seaweedfs = {
          enable = true;
          inherit port;
          domain = "fixture-seaweedfs.example.test";
          paths.dataDir = "/srv/seaweed";
          masterPort = 29333;
        };
      }
    ]).config;
in
  serviceContract {
    id = "seaweedfs";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.systemd.services ? seaweedfs;
  }
  // {
    backupCoversAllComponents = cfg.nixstead.serviceRegistry.seaweedfs.backup.paths == ["/srv/seaweed"];
    backupRequiresFilerShards = cfg.nixstead.serviceRegistry.seaweedfs.backup.requiredFiles == ["filer/00/CURRENT" "filer/01/CURRENT" "filer/02/CURRENT" "filer/03/CURRENT" "filer/04/CURRENT" "filer/05/CURRENT" "filer/06/CURRENT" "filer/07/CURRENT"];
    backupStopsAllWriters = cfg.nixstead.serviceRegistry.seaweedfs.backup.units == ["seaweedfs.service"];
    mountRequired = lib.elem "/srv/seaweed" cfg.systemd.services.seaweedfs.unitConfig.RequiresMountsFor;
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.seaweedfs.port = 70000;}]).config.nixstead.services.dev.seaweedfs.port).success;

    nativeFilerListener = lib.hasInfix "-filer.port=${toString port}" cfg.systemd.services.seaweedfs.serviceConfig.ExecStart;
    nativeMasterListener = lib.hasInfix "-master.port=29333" cfg.systemd.services.seaweedfs.serviceConfig.ExecStart;
    nativeBindAddress = lib.hasInfix "-ip.bind=127.0.0.1" cfg.systemd.services.seaweedfs.serviceConfig.ExecStart;
    nativeDataPaths = lib.all (flag: lib.hasInfix flag cfg.systemd.services.seaweedfs.serviceConfig.ExecStart) ["-master.dir=/srv/seaweed/master" "-dir=/srv/seaweed/volume"];
    nativeFilerStorage = lib.hasInfix "[leveldb2]" cfg.environment.etc."seaweedfs/filer.toml".text && lib.hasInfix "dir = \"/srv/seaweed/filer\"" cfg.environment.etc."seaweedfs/filer.toml".text;
    supportedCommandFlags = !(lib.hasInfix "-filer.dir=" cfg.systemd.services.seaweedfs.serviceConfig.ExecStart) && lib.hasInfix "-config_dir=/etc/seaweedfs" cfg.systemd.services.seaweedfs.serviceConfig.ExecStart;
    conflictingPortsRejected =
      lib.any (item: !item.assertion && lib.hasInfix "must be different" item.message)
      (mkSystem [
        {
          nixstead.services.dev.seaweedfs = {
            enable = true;
            port = 8888;
            masterPort = 8888;
          };
        }
      ]).config.assertions;
  }
