{
  config,
  host,
  lib,
  secretPlaceholder,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev;
  giteaStateDir =
    if cfg.gitea.paths.stateDir != null
    then cfg.gitea.paths.stateDir
    else config.services.gitea.stateDir;
  giteaAppIni = "${giteaStateDir}/custom/conf/app.ini";
in {
  config = lib.mkIf cfg.gitea.enable {
    sops.secrets = {
      "gitea/initialAdmin/username" = {};
      "gitea/initialAdmin/email" = {};
      "gitea/initialAdmin/password" = {};
    };

    sops.templates."gitea-initial-admin.env" = {
      owner = config.services.gitea.user;
      content = ''
        GITEA_ADMIN_USERNAME=${secretPlaceholder "gitea/initialAdmin/username"}
        GITEA_ADMIN_EMAIL=${secretPlaceholder "gitea/initialAdmin/email"}
        GITEA_ADMIN_PASSWORD=${secretPlaceholder "gitea/initialAdmin/password"}
      '';
      restartUnits = ["gitea.service"];
    };

    services.gitea =
      {
        enable = true;
        settings = {
          server = {
            DOMAIN = config.nixstead.services.dev.gitea.domain;
            ROOT_URL = "https://${config.nixstead.services.dev.gitea.domain}";
            HTTP_ADDR = serviceBindAddress "gitea";
            HTTP_PORT = config.nixstead.services.dev.gitea.port;
          };
          service = {
            DISABLE_REGISTRATION = true;
          };
        };
      }
      // lib.optionalAttrs (cfg.gitea.paths.stateDir != null) {
        stateDir = cfg.gitea.paths.stateDir;
      };

    systemd.services.gitea.serviceConfig.EnvironmentFile = [config.sops.templates."gitea-initial-admin.env".path];
    systemd.services.gitea.unitConfig.RequiresMountsFor = lib.optional (cfg.gitea.paths.stateDir != null) cfg.gitea.paths.stateDir;
    systemd.services.gitea.postStart = lib.mkAfter ''
      admin_username="$GITEA_ADMIN_USERNAME"
      admin_email="$GITEA_ADMIN_EMAIL"
      admin_password="$GITEA_ADMIN_PASSWORD"

      if [ -z "$admin_username" ] || [ -z "$admin_email" ] || [ -z "$admin_password" ]; then
        exit 0
      fi

      if ${config.services.gitea.package}/bin/gitea admin user list --config ${lib.escapeShellArg giteaAppIni} | grep -q " $admin_username "; then
        exit 0
      fi

      ${config.services.gitea.package}/bin/gitea admin user create \
        --config ${lib.escapeShellArg giteaAppIni} \
        --username "$admin_username" \
        --email "$admin_email" \
        --password "$admin_password" \
        --admin \
        --must-change-password=false
    '';

    users.users.${config.services.gitea.user}.extraGroups = [config.nixstead.host.groups.media];
  };
}
