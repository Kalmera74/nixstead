{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixstead.services.arr.credentials;
  arr = config.nixstead.services.arr;
  automatic = cfg.autoSync;
  selected = lib.filterAttrs (id: entry: entry.enabled && ((cfg.enable && entry.api != null) || id == "qbittorrent")) config.nixstead.serviceRegistry;
  active = automatic.enable && selected != {};
  declaredSource = toString config.nixstead.secrets.sopsFile;
  repositorySource = "${toString ../../..}/";
  defaultSource =
    if lib.hasPrefix repositorySource declaredSource
    then "${config.nixstead.host.repositoryPath}/${lib.removePrefix repositorySource declaredSource}"
    else if !lib.hasPrefix "/nix/store/" declaredSource
    then declaredSource
    else null;
  source =
    if automatic.sourceFile == null
    then "/run/nixstead-missing-credential-source"
    else automatic.sourceFile;
  runtime = "/run/nixstead-credential-enrollment";
  python = pkgs.python3.withPackages (ps: [ps.pyyaml ps.configobj]);
  specification = pkgs.writeText "nixstead-credential-enrollment.json" (builtins.toJSON {
    sourceFile = source;
    documentFile = automatic.documentFile;
    runtimeDirectory = runtime;
    ageKeyFile = config.sops.age.keyFile;
    sshKeyPaths = config.sops.age.sshKeyPaths;
    registry = lib.mapAttrs (_: entry: {inherit (entry) api;}) selected;
  });
  command = "${python}/bin/python3 ${./.}/credential_enrollment.py ${specification}";
  common = {
    path = [pkgs.sops pkgs.ssh-to-age pkgs.systemd];
    unitConfig.RequiresMountsFor = [source] ++ lib.concatMap (entry: lib.optional (entry.api != null) (builtins.dirOf entry.api.stateFile)) (lib.attrValues selected);
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [runtime (builtins.dirOf source)];
      PrivateTmp = true;
      NoNewPrivileges = true;
      TimeoutStartSec = 90;
    };
  };
in {
  options.nixstead.services.arr.credentials.autoSync = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable || arr.qbittorrent.enable;
      description = "Enroll missing credentials into the writable host SOPS file before application startup, then deliver its saved values automatically. Enabled with shared credentials; false keeps explicit sync and rebuild deployment.";
    };
    sourceFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = defaultSource;
      description = "Writable encrypted source corresponding to nixstead.secrets.sopsFile. Repository files are mapped to host.repositoryPath; external source paths and both encrypted-directory overrides are preserved. Set this explicitly for a consumer flake whose source checkout cannot be inferred; never use a Nix store path.";
    };
    documentFile = lib.mkOption {
      type = lib.types.str;
      default = "${runtime}/document.json";
      readOnly = true;
      internal = true;
      description = "Restricted runtime projection read back from the verified encrypted SOPS source.";
    };
  };
  config = lib.mkIf active {
    assertions = [
      {
        assertion = config.nixstead.secrets.enable;
        message = "Automatic credential enrollment requires nixstead.secrets.enable and an encrypted source decryptable by this host.";
      }
      {
        assertion = automatic.sourceFile != null && lib.hasPrefix "/" source && !lib.hasPrefix "/nix/store/" source;
        message = "arr.credentials.autoSync.sourceFile must be an absolute writable source path outside /nix/store.";
      }
      {
        assertion = cfg.documentFile == "/run/secrets/nixstead/credential-document";
        message = "A test credential document requires arr.credentials.autoSync.enable = false.";
      }
    ];
    systemd.services = {
      nixstead-credentials-sync = lib.mkMerge [
        common
        {
          description = "Enroll canonical credentials in SOPS before starting applications";
          after = ["sops-install-secrets.service"];
          wantedBy = ["multi-user.target"];
          # The refresh unit applies updated configuration without stopping every
          # application's dependency on the successful initial enrollment.
          restartIfChanged = false;
          serviceConfig = {
            RemainAfterExit = true;
            RuntimeDirectory = "nixstead-credential-enrollment";
            RuntimeDirectoryMode = "0700";
            RuntimeDirectoryPreserve = true;
            ExecStart = command;
          };
        }
      ];
      nixstead-credentials-sync-refresh = lib.mkMerge [
        common
        {
          description = "Refresh SOPS enrollment and shared runtime credentials";
          after = ["nixstead-credentials-sync.service"];
          requires = ["nixstead-credentials-sync.service"];
          wantedBy = ["multi-user.target"];
          restartTriggers = [specification config.nixstead.secrets.sopsFile];
          serviceConfig.ExecStart = "${command} --refresh";
        }
      ];
    };
    systemd.timers.nixstead-credentials-sync = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitInactiveSec = "1m";
        AccuracySec = "10s";
        Unit = "nixstead-credentials-sync-refresh.service";
      };
    };
  };
}
