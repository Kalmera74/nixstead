{
  config,
  host,
  lib,
  secretPlaceholder,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev;
  forgejoStateDir =
    if cfg.forgejo.paths.stateDir != null
    then cfg.forgejo.paths.stateDir
    else config.services.forgejo.stateDir;
  forgejoAppIni = "${forgejoStateDir}/custom/conf/app.ini";
in {
  config = lib.mkIf cfg.forgejo.enable {
    sops.secrets = {
      "forgejo/initialAdmin/username" = {};
      "forgejo/initialAdmin/email" = {};
      "forgejo/initialAdmin/password" = {};
    };

    sops.templates."forgejo-initial-admin.env" = {
      owner = config.services.forgejo.user;
      content = ''
        FORGEJO_ADMIN_USERNAME=${secretPlaceholder "forgejo/initialAdmin/username"}
        FORGEJO_ADMIN_EMAIL=${secretPlaceholder "forgejo/initialAdmin/email"}
        FORGEJO_ADMIN_PASSWORD=${secretPlaceholder "forgejo/initialAdmin/password"}
      '';
      restartUnits = ["forgejo.service"];
    };

    services.forgejo =
      {
        enable = true;
        settings = {
          server = {
            DOMAIN = config.nixstead.services.dev.forgejo.domain;
            ROOT_URL = "https://${config.nixstead.services.dev.forgejo.domain}";
            HTTP_ADDR = serviceBindAddress "forgejo";
            HTTP_PORT = config.nixstead.services.dev.forgejo.port;
          };
          service = {
            DISABLE_REGISTRATION = true;
          };
        };
      }
      // lib.optionalAttrs (cfg.forgejo.paths.stateDir != null) {
        stateDir = cfg.forgejo.paths.stateDir;
      }
      // lib.optionalAttrs (cfg.forgejo.paths.repositoryDir != null) {
        repositoryRoot = cfg.forgejo.paths.repositoryDir;
      };

    systemd.services.forgejo.serviceConfig.EnvironmentFile = [config.sops.templates."forgejo-initial-admin.env".path];
    systemd.services.forgejo.unitConfig.RequiresMountsFor = lib.filter (path: path != null) [
      cfg.forgejo.paths.stateDir
      cfg.forgejo.paths.repositoryDir
    ];
    systemd.services.forgejo.postStart = lib.mkAfter ''
      admin_username="$FORGEJO_ADMIN_USERNAME"
      admin_email="$FORGEJO_ADMIN_EMAIL"
      admin_password="$FORGEJO_ADMIN_PASSWORD"

      if [ -z "$admin_username" ] || [ -z "$admin_email" ] || [ -z "$admin_password" ]; then
        exit 0
      fi

      if ${config.services.forgejo.package}/bin/forgejo admin user list --config ${lib.escapeShellArg forgejoAppIni} | grep -q " $admin_username "; then
        exit 0
      fi

      ${config.services.forgejo.package}/bin/forgejo admin user create \
        --config ${lib.escapeShellArg forgejoAppIni} \
        --username "$admin_username" \
        --email "$admin_email" \
        --password "$admin_password" \
        --admin \
        --must-change-password=false
    '';

    users.users.${config.services.forgejo.user}.extraGroups = [config.nixstead.host.groups.media];
  };
}
