{
  config,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev.ntfy;
  dataDir = cfg.paths.dataDir;
  generatePassword = cfg.adminPasswordFile == null;
  passwordFile =
    if generatePassword
    then "${dataDir}/admin-password"
    else cfg.adminPasswordFile;
  environmentFile = "${dataDir}/auth.env";
  bootstrapCredentials = ''
    set -euo pipefail

    install -d -m 0750 ${lib.escapeShellArg dataDir}

    ${lib.optionalString generatePassword ''
      if [ ! -s ${lib.escapeShellArg passwordFile} ]; then
        umask 077
        ${pkgs.openssl}/bin/openssl rand -hex 24 > ${lib.escapeShellArg "${passwordFile}.tmp"}
        mv -f ${lib.escapeShellArg "${passwordFile}.tmp"} ${lib.escapeShellArg passwordFile}
      fi
    ''}

    IFS= read -r password < ${
      if generatePassword
      then lib.escapeShellArg passwordFile
      else ''"$CREDENTIALS_DIRECTORY/admin-password"''
    } || [ -n "$password" ]
    if [ -z "$password" ]; then
      echo "The ntfy administrator password file must not be empty." >&2
      exit 1
    fi
    password_hash="$(
      printf '%s\n%s\n' "$password" "$password" \
        | ${lib.getExe config.services.ntfy-sh.package} user hash
    )"
    unset password

    umask 077
    printf 'NTFY_AUTH_USERS=%s:%s:admin\n' \
      ${lib.escapeShellArg cfg.adminUsername} \
      "$password_hash" > ${lib.escapeShellArg "${environmentFile}.tmp"}
    mv -f ${lib.escapeShellArg "${environmentFile}.tmp"} ${lib.escapeShellArg environmentFile}
  '';
in {
  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      inherit environmentFile;
      settings = {
        "base-url" = "https://${cfg.domain}";
        "listen-http" = "${serviceBindAddress "ntfy"}:${toString cfg.port}";
        "behind-proxy" = true;
        "auth-file" = "${dataDir}/user.db";
        "auth-default-access" = "deny-all";
        "cache-file" = "${dataDir}/cache.db";
        "attachment-cache-dir" = "${dataDir}/attachments";
      };
    };

    systemd.services = {
      ntfy-bootstrap-credentials = {
        description = "Generate the ntfy bootstrap administrator credential";
        before = ["ntfy-sh.service"];
        unitConfig.RequiresMountsFor = [dataDir passwordFile];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Share the native private state namespace during first start and
          # clean restore, before generating or reading persistent credentials.
          User = config.services.ntfy-sh.user;
          Group = config.services.ntfy-sh.group;
          DynamicUser = true;
          StateDirectory = "ntfy-sh";
          StateDirectoryMode = "0750";
          LoadCredential = lib.optional (!generatePassword) "admin-password:${cfg.adminPasswordFile}";
        };
        script = bootstrapCredentials;
      };

      ntfy-sh = {
        requires = ["ntfy-bootstrap-credentials.service"];
        after = ["ntfy-bootstrap-credentials.service"];
        unitConfig.RequiresMountsFor = [dataDir passwordFile];
      };
    };
  };
}
