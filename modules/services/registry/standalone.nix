{
  mkService,
  localProxy,
  card,
  health,
  backup,
  setup,
  credential,
  ...
}: {
  vaultwarden = mkService {
    name = "Vaultwarden";
    optionPath = ["vaultwarden"];
    defaults = {
      subdomain = "vaultwarden";
      port = 8222;
      backup = {
        user = "vaultwarden";
        group = "vaultwarden";
        schedule = "23:00";
      };
    };
    firewall = true;
    proxy = localProxy // {websockets = true;};
    homepage = card "Standalone" 10 "Vaultwarden" "vaultwarden" "Passwords";
    health = health "vaultwarden.service";
    secrets = ["vaultwarden"];
    credentials = [
      (credential.sops "admin token" ["vaultwarden" "adminToken"])
    ];
    backup =
      (backup "vaultwarden" "vaultwarden.service" "vaultwarden" "vaultwarden")
      // {
        nativePathOption = ["systemd" "services" "vaultwarden" "environment" "DATA_FOLDER"];
        defaultPath = "/var/lib/vaultwarden";
        ownerOption = ["systemd" "services" "vaultwarden" "serviceConfig" "User"];
        groupOption = ["systemd" "services" "vaultwarden" "serviceConfig" "Group"];
        requiredFilesWhenNativeEquals = [
          {
            option = ["services" "vaultwarden" "dbBackend"];
            value = "sqlite";
            extraMatches = [
              {
                option = ["services" "vaultwarden" "config" "DATABASE_URL"];
                value = null;
              }
              {
                option = ["services" "vaultwarden" "config" "databaseUrl"];
                value = null;
              }
            ];
            files = ["db.sqlite3"];
          }
          {
            option = ["services" "vaultwarden" "config" "RSA_KEY_FILENAME"];
            value = null;
            extraMatches = [
              {
                option = ["services" "vaultwarden" "config" "rsaKeyFilename"];
                value = null;
              }
            ];
            files = ["rsa_key.pem"];
          }
        ];
      };
    setup = setup "standalone" 510 ["full"];
  };

  homeassistant = mkService {
    name = "Home Assistant";
    optionPath = ["homeassistant"];
    defaults = {
      subdomain = "homeassistant";
      port = 8123;
    };
    firewall = true;
    proxy =
      localProxy
      // {
        websockets = true;
        extraLocationConfig = ''
          proxy_buffering off;
        '';
      };
    homepage = card "Standalone" 20 "Home Assistant" "home-assistant" "Home Automation";
    health = health "home-assistant.service";
    credentials = [
      (credential.manual "Create the first Home Assistant owner account in the onboarding web flow.")
    ];
    # Keep common native identity/configuration inputs, but only require the
    # default recorder/provider files when native configuration selects them.
    backup =
      (backup "homeassistant" "home-assistant.service" "hass" "hass")
      // {
        requiredFiles = ["configuration.yaml" ".storage/auth" ".storage/onboarding"];
        requiredFilesWhenNativeEquals = [
          {
            option = ["services" "home-assistant" "config" "recorder" "db_url"];
            value = null;
            files = ["home-assistant_v2.db"];
          }
          {
            option = ["services" "home-assistant" "config" "homeassistant" "auth_providers"];
            value = null;
            files = [".storage/auth_provider.homeassistant"];
          }
          {
            option = ["services" "home-assistant" "config" "homeassistant" "auth_providers"];
            value = [{type = "homeassistant";}];
            files = [".storage/auth_provider.homeassistant"];
          }
        ];
      };
    setup = setup "standalone" 520 ["full"];
  };

  authentik = mkService {
    name = "authentik";
    optionPath = ["authentik"];
    defaults = {
      subdomain = "auth";
      port = 9000;
      workerPort = 9001;
      metricsPort = 9300;
      workerMetricsPort = 9301;
      httpsPort = 9443;
    };
    listeners.settingsTcpPorts = ["port" "workerPort" "metricsPort" "workerMetricsPort" "httpsPort"];
    firewall = true;
    proxy = localProxy // {websockets = true;};
    homepage = card "Standalone" 30 "authentik" "authentik" "Identity Provider";
    health = health "authentik-server.service";
    secrets = ["authentik"];
    credentials = [
      (credential.manual "Create the initial authentik administrator through the first-start setup flow; the SOPS secretKey is not a login password.")
    ];
    backup =
      (backup "authentik" "authentik-server.service" "authentik" "authentik")
      // {
        units = ["authentik-server.service" "authentik-worker.service"];
        database = "postgresql";
        databasePortOption = ["services" "postgresql" "settings" "port"];
        databaseName = "authentik";
        databaseUnit = "postgresql.service";
      };
    setup = setup "standalone" 530 [];
  };

  syncthing = mkService {
    name = "Syncthing";
    optionPath = ["syncthing"];
    defaults = {
      subdomain = "syncthing";
      port = 8384;
      transferPort = 22000;
      discoveryPort = 21027;
    };
    listeners = {
      settingsTcpPorts = ["port" "transferPort"];
      settingsUdpPorts = ["transferPort" "discoveryPort"];
    };
    firewall = {
      settingsTcpPorts = ["transferPort"];
      settingsUdpPorts = ["transferPort" "discoveryPort"];
    };
    proxy =
      localProxy
      // {
        websockets = true;
        hostHeader = "localhost";
      };
    homepage = card "Standalone" 40 "Syncthing" "syncthing" "Device File Sync";
    health = health "syncthing.service";
    credentials = [
      (credential.option "username" ["guiUsername"])
      (credential.file {
        label = "password";
        path = "/var/lib/syncthing/.config/syncthing/gui-password";
        pathOption = ["guiPasswordFile"];
        fallbackPathOption = ["paths" "configDir"];
        suffix = "/gui-password";
      })
    ];
    backup =
      (backup "syncthing" "syncthing.service" "syncthing" "syncthing")
      // {
        pathOption = ["paths" "configDir"];
        ownerOption = ["services" "syncthing" "user"];
        groupOption = ["services" "syncthing" "group"];
        requiredFiles = ["config.xml" "cert.pem" "key.pem"];
        requiredFilesWhenNull = [
          {
            option = ["guiPasswordFile"];
            files = ["gui-password"];
          }
        ];
      };
    setup = setup "standalone" 540 ["full"];
  };

  scrutiny = mkService {
    name = "Scrutiny";
    optionPath = ["scrutiny"];
    defaults = {
      subdomain = "scrutiny";
      port = 8192;
      influxdbPort = 8086;
    };
    listeners.settingsTcpPorts = ["port" "influxdbPort"];
    firewall = true;
    proxy = localProxy;
    homepage = card "Infrastructure" 60 "Scrutiny" "scrutiny" "Drive Health";
    health = health "scrutiny.service";
    backup =
      (backup "scrutiny" "scrutiny.service" "root" "root")
      // {
        units = ["scrutiny.service" "influxdb2.service"];
        extraPathOptions = [["paths" "influxdbDir"]];
      };
    setup = setup "standalone" 550 ["full"];
  };
}
