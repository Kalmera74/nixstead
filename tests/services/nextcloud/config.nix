{
  lib,
  mkSystem,
  serviceContract,
  ...
}: let
  config =
    (mkSystem [
      {
        nixstead.services.productivity.nextcloud = {
          enable = true;
          paths.dataDir = "/srv/cloud-data";
          adminPasswordFile = "/run/credentials/cloud-admin";
        };
        services.nextcloud.home = "/srv/cloud-home";
      }
    ]).config;
in
  (serviceContract {
    id = "nextcloud";
    group = "productivity";
    port = 28083;
    nativeEnabled = c: c.services.nextcloud.enable;
  })
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.nextcloud.port = 70000;}]).config.nixstead.services.productivity.nextcloud.port).success;
    separateNativeHome = config.services.nextcloud.home == "/srv/cloud-home";
    defaultSqliteProfile = config.services.nextcloud.config.dbtype == "sqlite";
    nativeHttpDoesNotRequireManagedTls = !config.nixstead.services.nginx.enable && config.services.nginx.enable && !config.services.nginx.virtualHosts.${config.services.nextcloud.hostName}.forceSSL && !config.services.nginx.virtualHosts.${config.services.nextcloud.hostName}.addSSL && !config.services.nginx.virtualHosts.${config.services.nextcloud.hostName}.onlySSL;
    separateStateCovered = config.nixstead.serviceRegistry.nextcloud.backup.paths == ["/srv/cloud-home" "/srv/cloud-data"];
    credentialOverride = config.services.nextcloud.config.adminpassFile == "/run/credentials/cloud-admin";
    noCompetingGenerator = !(config.system.activationScripts ? nextcloud-admin-pass);
    customDataDirectory = config.services.nextcloud.datadir == "/srv/cloud-data";
    runtimeMountDependencies = lib.elem "/srv/cloud-data" config.systemd.services.nextcloud-setup.unitConfig.RequiresMountsFor;
  }
