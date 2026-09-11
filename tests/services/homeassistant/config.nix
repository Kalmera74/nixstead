{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  c =
    (mkSystem [
      {
        nixstead.services.homeassistant = {
          enable = true;
          port = 28123;
          paths.dataDir = "/srv/automation";
        };
      }
    ]).config;
  backupWith = native:
    (mkSystem [
      {
        nixstead.services.homeassistant.enable = true;
        services.home-assistant.config = native;
      }
    ]).config.nixstead.serviceRegistry.homeassistant.backup;
  externalRecorder = backupWith {recorder.db_url = "postgresql://fixture@database/fixture";};
  relocatedRecorder = backupWith {recorder.db_url = "sqlite:////srv/history/custom.sqlite";};
  customProvider = backupWith {
    homeassistant.auth_providers = [
      {
        type = "command_line";
        command = "/run/fixture-auth";
      }
    ];
  };
  explicitLocalProvider = backupWith {homeassistant.auth_providers = [{type = "homeassistant";}];};
in
  (serviceContract {
    id = "homeassistant";
    port = 28123;
    nativeEnabled = c: c.services.home-assistant.enable;
  })
  // {
    nativeStateAndArchive = c.services.home-assistant.configDir == "/srv/automation" && c.nixstead.serviceRegistry.homeassistant.backup.paths == ["/srv/automation"];
    nativeListener = c.services.home-assistant.config.http.server_host == "127.0.0.1" && c.services.home-assistant.config.http.server_port == 28123;
    onlyLocalProxyTrusted = c.services.home-assistant.config.http.use_x_forwarded_for && c.services.home-assistant.config.http.trusted_proxies == ["127.0.0.1" "::1"];
    waitsForStateMount = c.systemd.services.home-assistant.unitConfig.RequiresMountsFor == "/srv/automation";
    nativeRestoreOwner = c.nixstead.serviceRegistry.homeassistant.backup.owner == "hass" && c.nixstead.serviceRegistry.homeassistant.backup.group == "hass";
    localIdentityAndRecorderRequired = c.nixstead.serviceRegistry.homeassistant.backup.requiredFiles == ["configuration.yaml" ".storage/auth" ".storage/onboarding" "home-assistant_v2.db" ".storage/auth_provider.homeassistant"];
    externalRecorderOmitsDefaultDatabase = !(lib.elem "home-assistant_v2.db" externalRecorder.requiredFiles) && lib.elem ".storage/auth_provider.homeassistant" externalRecorder.requiredFiles;
    relocatedRecorderOmitsDefaultDatabase = !(lib.elem "home-assistant_v2.db" relocatedRecorder.requiredFiles);
    customProviderOmitsLocalPasswordStore = !(lib.elem ".storage/auth_provider.homeassistant" customProvider.requiredFiles) && lib.elem "home-assistant_v2.db" customProvider.requiredFiles;
    explicitLocalProviderRequiresPasswordStore = lib.elem ".storage/auth_provider.homeassistant" explicitLocalProvider.requiredFiles;
    relativeStateRejected = !(builtins.tryEval (mkSystem [{nixstead.services.homeassistant.paths.dataDir = "relative/state";}]).config.nixstead.services.homeassistant.paths.dataDir).success;
  }
