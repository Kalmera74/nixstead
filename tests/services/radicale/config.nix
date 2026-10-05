{
  lib,
  mkSystem,
  serviceContract,
  ...
}: let
  port = 25232;
  cfg =
    (mkSystem [
      {
        nixstead.services.productivity.radicale = {
          enable = true;
          inherit port;
          domain = "calendar.example.test";
          paths.dataDir = "/srv/radicale";
          usersFile = "/run/secrets/radicale/users";
        };
        nixstead.services.nginx.enable = true;
      }
    ]).config;
  generated = (mkSystem [{nixstead.services.productivity.radicale.enable = true;}]).config;
  exposed =
    (mkSystem [
      {
        nixstead.services.productivity.radicale.enable = true;
        nixstead.host.network.exposure.services.radicale = "public";
      }
    ]).config;
  parent = (mkSystem [{nixstead.services.productivity.enable = true;}]).config;
  preset = (mkSystem [{nixstead.preset = "full";}]).config;
  vhost = cfg.services.nginx.virtualHosts."calendar.example.test";
in
  serviceContract {
    id = "radicale";
    group = "productivity";
    inherit port;
    nativeEnabled = c: c.services.radicale.enable;
  }
  // {
    parentEnablesChild = parent.services.radicale.enable;
    fullPresetEnablesChild = preset.services.radicale.enable;
    nativeListener = cfg.services.radicale.settings.server.hosts == ["127.0.0.1:${toString port}"];
    publicListener = exposed.services.radicale.settings.server.hosts == ["0.0.0.0:5232"];
    nativeStorage = cfg.services.radicale.settings.storage.filesystem_folder == "/srv/radicale/collections";
    customStorageWritable = lib.elem "/srv/radicale" cfg.systemd.services.radicale.serviceConfig.ReadWritePaths;
    customStorageCreated = cfg.systemd.tmpfiles.settings."10-radicale"."/srv/radicale/collections".d.user == "radicale";
    customWorkingDirectory = cfg.systemd.services.radicale.serviceConfig.WorkingDirectory == "/srv/radicale";
    runtimeCredential = cfg.systemd.services.radicale.serviceConfig.LoadCredential == ["users:/run/secrets/radicale/users"];
    runtimeCredentialConsumer = cfg.services.radicale.settings.auth.htpasswd_filename == "/run/credentials/radicale.service/users";
    noCompetingGenerator = cfg.systemd.services.radicale.preStart == "";
    generatedCredential = generated.services.radicale.settings.auth.htpasswd_filename == "/var/lib/radicale/users" && lib.hasInfix "htpasswd -niB admin" generated.systemd.services.radicale.preStart;
    bcryptAuthentication = cfg.services.radicale.settings.auth.type == "htpasswd" && cfg.services.radicale.settings.auth.htpasswd_encryption == "bcrypt";
    privateCollections = cfg.services.radicale.settings.rights.type == "owner_only";
    discoveryRedirects = lib.hasInfix "location = /.well-known/caldav { return 301 /; }" vhost.extraConfig && lib.hasInfix "location = /.well-known/carddav { return 301 /; }" vhost.extraConfig;
    proxyUsesCustomPort = vhost.locations."/".proxyPass == "http://127.0.0.1:${toString port}";
    backupFollowsStorage = cfg.nixstead.serviceRegistry.radicale.backup.paths == ["/srv/radicale"];
    externalCredentialsNotRequiredInArchive = cfg.nixstead.serviceRegistry.radicale.backup.requiredFiles == [];
    generatedCredentialsRequiredInArchive = generated.nixstead.serviceRegistry.radicale.backup.requiredFiles == ["users" "admin-password"];
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.radicale.port = 70000;}]).config.nixstead.services.productivity.radicale.port).success;
  }
