{
  config,
  lib,
  optionalRuntimePathOption,
  pkgs,
  runtimePathOption,
  serviceOptionFromRegistry,
  serviceRegistry,
  ...
}: let
  cfg = config.nixstead.services.syncthing;
  generatePassword = cfg.guiPasswordFile == null;
  passwordFile =
    if generatePassword
    then "${cfg.paths.configDir}/gui-password"
    else cfg.guiPasswordFile;
  bootstrapPassword = pkgs.writeShellScript "syncthing-bootstrap-password" ''
    set -euo pipefail

    install -d -m 0750 \
      -o ${lib.escapeShellArg cfg.user} \
      -g ${lib.escapeShellArg cfg.group} \
      ${lib.escapeShellArg cfg.paths.dataDir}
    install -d -m 0700 \
      -o ${lib.escapeShellArg cfg.user} \
      -g ${lib.escapeShellArg cfg.group} \
      ${lib.escapeShellArg cfg.paths.configDir}

    ${lib.optionalString generatePassword ''
      if [ ! -s ${lib.escapeShellArg passwordFile} ]; then
        umask 077
        ${pkgs.openssl}/bin/openssl rand -hex 24 > ${lib.escapeShellArg "${passwordFile}.tmp"}
        chown ${lib.escapeShellArg "${cfg.user}:${cfg.group}"} ${lib.escapeShellArg "${passwordFile}.tmp"}
        mv -f ${lib.escapeShellArg "${passwordFile}.tmp"} ${lib.escapeShellArg passwordFile}
      fi
    ''}
  '';
in {
  options.nixstead.services.syncthing = serviceOptionFromRegistry "syncthing" {
    pathOptions = {
      dataDir = runtimePathOption "/var/lib/syncthing" "Absolute base directory for Syncthing state and default synchronized folders.";
      configDir = runtimePathOption "/var/lib/syncthing/.config/syncthing" "Absolute directory containing Syncthing configuration, indexes, keys, and GUI credentials.";
    };
    extraOptions = {
      user = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "syncthing";
        description = "User account that runs Syncthing.";
      };
      group = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "syncthing";
        description = "Primary group used by Syncthing.";
      };
      guiUsername = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9._-]+";
        default = "admin";
        description = "Username used to authenticate to the Syncthing web interface.";
      };
      guiPasswordFile = optionalRuntimePathOption "Optional absolute file containing the Syncthing GUI password, such as a sops-nix secret path; a password is generated when unset.";
      transferPort = lib.mkOption {
        type = lib.types.port;
        default = serviceRegistry.syncthing.defaults.transferPort;
        description = "TCP and QUIC port used for Syncthing device transfers.";
      };
      discoveryPort = lib.mkOption {
        type = lib.types.port;
        default = serviceRegistry.syncthing.defaults.discoveryPort;
        description = "UDP port used for Syncthing local discovery.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      inherit (cfg) user group;
      inherit (cfg.paths) dataDir configDir;
      databaseDir = cfg.paths.configDir;
      guiAddress = "127.0.0.1:${toString cfg.port}";
      guiPasswordFile = passwordFile;
      openDefaultPorts = false;
      overrideDevices = false;
      overrideFolders = false;
      settings = {
        gui = {
          user = cfg.guiUsername;
          insecureAdminAccess = false;
        };
        options = {
          listenAddresses = [
            "tcp://0.0.0.0:${toString cfg.transferPort}"
            "quic://0.0.0.0:${toString cfg.transferPort}"
          ];
          localAnnouncePort = cfg.discoveryPort;
        };
      };
    };

    systemd.services = {
      syncthing-bootstrap-password = {
        description = "Generate the Syncthing GUI bootstrap password";
        before = ["syncthing.service"];
        unitConfig.RequiresMountsFor = [
          cfg.paths.dataDir
          cfg.paths.configDir
          passwordFile
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = bootstrapPassword;
        };
      };

      syncthing = {
        requires = ["syncthing-bootstrap-password.service"];
        after = ["syncthing-bootstrap-password.service"];
        unitConfig.RequiresMountsFor = [
          cfg.paths.dataDir
          cfg.paths.configDir
        ];
      };
    };
  };
}
