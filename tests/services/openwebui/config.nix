{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  external =
    (mkSystem [
      {
        nixstead.services.localai.openwebui = {
          enable = true;
          port = 28081;
          ollamaUrl = "https://models.example.test:11435";
          environmentFile = "/run/secrets/webui.env";
        };
      }
    ]).config;
  local =
    (mkSystem [
      {
        nixstead.services.localai = {
          ollama = {
            enable = true;
            port = 21434;
          };
          openwebui.enable = true;
        };
      }
    ]).config;
  relocated =
    (mkSystem [
      {
        nixstead.services.localai.openwebui = {
          enable = true;
          ollamaUrl = "http://models.example.test";
        };
        services.open-webui.stateDir = "/var/lib/open-webui-fixture";
      }
    ]).config;
  nativeBackup = environment:
    (mkSystem [
      {
        nixstead.services.localai.openwebui = {
          enable = true;
          ollamaUrl = "http://models.example.test";
        };
        services.open-webui = {inherit environment;};
      }
    ]).config.nixstead.serviceRegistry.openwebui.backup;
  rejects = settings: lib.any (a: !a.assertion && lib.hasInfix "Open WebUI requires" a.message) (mkSystem [{nixstead.services.localai.openwebui = {enable = true;} // settings;}]).config.assertions;
in
  (serviceContract {
    id = "openwebui";
    group = "localai";
    port = 28081;
    extra.nixstead.services.localai.openwebui.ollamaUrl = "http://models.example.test:11434";
    nativeEnabled = c: c.services.open-webui.enable;
  })
  // {
    externalDoesNotStartOllama = !external.services.ollama.enable && external.services.open-webui.environment.OLLAMA_BASE_URL == "https://models.example.test:11435";
    localUsesCustomPort = local.services.open-webui.environment.OLLAMA_BASE_URL == "http://127.0.0.1:21434";
    nativeListener = external.services.open-webui.host == "127.0.0.1" && external.services.open-webui.port == 28081;
    runtimeCredentials = external.services.open-webui.environmentFile == "/run/secrets/webui.env" && !(external.services.open-webui.environment ? WEBUI_ADMIN_PASSWORD);
    nativeStateAndKeyDirectory = local.systemd.services.open-webui.environment.DATA_DIR == "/var/lib/open-webui/data" && local.systemd.services.open-webui.serviceConfig.WorkingDirectory == "/var/lib/open-webui" && local.nixstead.serviceRegistry.openwebui.backup.paths == ["/var/lib/open-webui"];
    archiveFollowsNativeStateOverride = relocated.nixstead.serviceRegistry.openwebui.backup.paths == ["/var/lib/open-webui-fixture"];
    quiescedSqliteAndUploads = local.nixstead.serviceRegistry.openwebui.backup.units == ["open-webui.service"] && local.nixstead.serviceRegistry.openwebui.backup.requiredFiles == ["data/webui.db" ".webui_secret_key"] && local.nixstead.serviceRegistry.openwebui.backup.dynamicUser;
    opaqueRuntimeOverridesOmitDefaultRequirements = external.nixstead.serviceRegistry.openwebui.backup.requiredFiles == [];
    nativeExternalKeyOmitsGeneratedFile = (nativeBackup {WEBUI_SECRET_KEY = "configuration-only-placeholder";}).requiredFiles == ["data/webui.db"];
    nativeExternalDatabaseOmitsDefaultSqlite = (nativeBackup {DATABASE_URL = "postgresql://fixture@database/webui";}).requiredFiles == [".webui_secret_key"];
    redirectedDataOmitsDefaultSqlite = (nativeBackup {DATA_DIR = "/srv/webui-data";}).requiredFiles == [".webui_secret_key"];
    dependencyRequired = rejects {};
    invalidEndpointRejected = rejects {ollamaUrl = "file:///tmp/model";};
    relativeEnvironmentRejected = !(builtins.tryEval (mkSystem [{nixstead.services.localai.openwebui.environmentFile = "relative.env";}]).config.nixstead.services.localai.openwebui.environmentFile).success;
  }
