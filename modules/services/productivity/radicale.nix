{
  config,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity.radicale;
  native = config.services.radicale;
  dataDir = cfg.paths.dataDir;
  generateCredentials = cfg.usersFile == null;
  passwordFile = "${dataDir}/admin-password";
  usersFile = "${dataDir}/users";
in {
  config = lib.mkIf cfg.enable {
    services.radicale = {
      enable = true;
      settings = {
        server.hosts = ["${serviceBindAddress "radicale"}:${toString cfg.port}"];
        auth = {
          type = "htpasswd";
          htpasswd_encryption = "bcrypt";
          htpasswd_filename =
            if generateCredentials
            then usersFile
            else "/run/credentials/radicale.service/users";
        };
        rights.type = lib.mkDefault "owner_only";
        storage.filesystem_folder = "${dataDir}/collections";
      };
    };

    systemd.tmpfiles.settings."10-radicale" = {
      "${dataDir}".d = {
        mode = "0750";
        user = native.user;
        group = native.group;
      };
      "${dataDir}/collections".d = {
        mode = "0750";
        user = native.user;
        group = native.group;
      };
    };

    systemd.services.radicale = {
      unitConfig.RequiresMountsFor = [dataDir] ++ lib.optional (!generateCredentials) cfg.usersFile;
      serviceConfig = {
        WorkingDirectory = lib.mkForce dataDir;
        ReadWritePaths = [dataDir];
        LoadCredential = lib.optional (!generateCredentials) "users:${cfg.usersFile}";
      };
      preStart = lib.mkIf generateCredentials ''
        set -euo pipefail
        umask 077

        if [ ! -s ${lib.escapeShellArg usersFile} ]; then
          if [ ! -s ${lib.escapeShellArg passwordFile} ]; then
            ${pkgs.openssl}/bin/openssl rand -hex 24 > ${lib.escapeShellArg "${passwordFile}.tmp"}
            mv -f ${lib.escapeShellArg "${passwordFile}.tmp"} ${lib.escapeShellArg passwordFile}
          fi
          ${pkgs.apacheHttpd}/bin/htpasswd -niB admin < ${lib.escapeShellArg passwordFile} > ${lib.escapeShellArg "${usersFile}.tmp"}
          mv -f ${lib.escapeShellArg "${usersFile}.tmp"} ${lib.escapeShellArg usersFile}
        fi
      '';
    };
  };
}
