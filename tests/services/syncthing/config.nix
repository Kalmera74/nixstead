{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  settings = {
    enable = true;
    port = 28384;
    transferPort = 32000;
    discoveryPort = 31027;
    guiUsername = "fixture-admin";
    guiPasswordFile = "/run/secrets/sync-password";
    paths = {
      dataDir = "/srv/synced";
      configDir = "/srv/sync-identity";
    };
  };
  c = (mkSystem [{nixstead.services.syncthing = settings;}]).config;
  exposed =
    (mkSystem [
      {
        nixstead.services.syncthing = settings;
        nixstead.host.network.exposure.services.syncthing = "public";
      }
    ]).config;
  generated =
    (mkSystem [
      {
        nixstead.services.syncthing = {
          enable = true;
          paths.configDir = "/srv/sync-identity";
        };
      }
    ]).config;
  customIdentity =
    (mkSystem [
      {
        users.users.syncowner = {
          isSystemUser = true;
          group = "syncowners";
        };
        users.groups.syncowners = {};
        nixstead.services.syncthing = {
          enable = true;
          user = "syncowner";
          group = "syncowners";
        };
      }
    ]).config;
in
  (builtins.removeAttrs (serviceContract {
    id = "syncthing";
    port = 28384;
    nativeEnabled = c: c.services.syncthing.enable;
  }) ["publicOpensFirewall"])
  // {
    guiAlwaysLoopback = exposed.services.syncthing.guiAddress == "127.0.0.1:28384" && !(lib.elem 28384 exposed.networking.firewall.allowedTCPPorts);
    nativePeerPorts = c.services.syncthing.settings.options.listenAddresses == ["tcp://0.0.0.0:32000" "quic://0.0.0.0:32000"] && c.services.syncthing.settings.options.localAnnouncePort == 31027;
    publicPeerFirewall = lib.elem 32000 exposed.networking.firewall.allowedTCPPorts && lib.all (p: lib.elem p exposed.networking.firewall.allowedUDPPorts) [32000 31027];
    nativeDirectories = c.services.syncthing.dataDir == "/srv/synced" && c.services.syncthing.configDir == "/srv/sync-identity" && c.services.syncthing.databaseDir == "/srv/sync-identity";
    identityOnlyArchive = c.nixstead.serviceRegistry.syncthing.backup.paths == ["/srv/sync-identity"];
    cleanRestoreUsesNativeIdentity = c.nixstead.serviceRegistry.syncthing.backup.owner == "syncthing" && c.nixstead.serviceRegistry.syncthing.backup.group == "syncthing";
    customRestoreOwnership = customIdentity.nixstead.serviceRegistry.syncthing.backup.owner == "syncowner" && customIdentity.nixstead.serviceRegistry.syncthing.backup.group == "syncowners";
    incompleteIdentityArchiveRejected = c.nixstead.serviceRegistry.syncthing.backup.requiredFiles == ["config.xml" "cert.pem" "key.pem"];
    generatedGuiPasswordRequiredForRestore = generated.nixstead.serviceRegistry.syncthing.backup.requiredFiles == ["config.xml" "cert.pem" "key.pem" "gui-password"];
    runtimeGuiCredentials = c.services.syncthing.guiPasswordFile == "/run/secrets/sync-password" && c.services.syncthing.settings.gui.user == "fixture-admin" && !c.services.syncthing.settings.gui.insecureAdminAccess;
    generatedCredentialFollowsState = generated.services.syncthing.guiPasswordFile == "/srv/sync-identity/gui-password";
    preservesApplicationFolders = !c.services.syncthing.overrideDevices && !c.services.syncthing.overrideFolders;
    bootstrapOrdering = lib.elem "syncthing-bootstrap-password.service" c.systemd.services.syncthing.requires && lib.elem "/run/secrets/sync-password" c.systemd.services.syncthing-bootstrap-password.unitConfig.RequiresMountsFor;
    invalidUsernameRejected = !(builtins.tryEval (mkSystem [{nixstead.services.syncthing.guiUsername = "bad user";}]).config.nixstead.services.syncthing.guiUsername).success;
  }
