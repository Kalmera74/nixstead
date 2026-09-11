{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.arr.sabnzbd = {
      enable = true;
      port = 28108;
    };
    nixstead.services.arr.sabnzbd.paths.dataDir = "/var/lib/sab-custom";
    nixstead.services.arr.sabnzbd.secretFile = "/run/secrets/sab/settings.ini";
    nixstead.services.arr.credentials.enable = true;
  };
  config = (mkSystem [selected]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.sabnzbd = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "sabnzbd";
    group = "arr";
    port = 28108;
    nativeEnabled = c: c.services.sabnzbd.enable;
  })
  // {
    nativePort = config.services.sabnzbd.settings.misc.port == 28108;
    nativeLoopback = config.services.sabnzbd.settings.misc.host == "127.0.0.1";
    publicListener = public.services.sabnzbd.settings.misc.host == "0.0.0.0";
    nativeState = config.services.sabnzbd.stateDir == "sab-custom";
    backupCustomState = config.nixstead.serviceRegistry.sabnzbd.backup.paths == ["/var/lib/sab-custom"];
    runtimeCredentials = config.services.sabnzbd.secretFiles == ["/run/credentials/sabnzbd.service/settings.ini" "/run/credentials/sabnzbd.service/nixstead.ini"] && lib.elem "settings.ini:/run/secrets/sab/settings.ini" config.systemd.services.sabnzbd.serviceConfig.LoadCredential;
    privateState = config.systemd.services.sabnzbd.serviceConfig.StateDirectoryMode == "0700";
    writableMedia = config.services.sabnzbd.group == config.nixstead.host.groups.media && config.systemd.services.sabnzbd.serviceConfig.UMask == "0002";
    outsideStateRejected = rejects "SABnzbd state must" {nixstead.services.arr.sabnzbd.paths.dataDir = lib.mkForce "/srv/sab";};
    privateStateRejected = rejects "SABnzbd state must" {nixstead.services.arr.sabnzbd.paths.dataDir = lib.mkForce "/var/lib/private/sab";};
    traversalRejected = rejects "SABnzbd state must" {nixstead.services.arr.sabnzbd.paths.dataDir = lib.mkForce "/var/lib/../sab";};
    nativeMismatchRejected = rejects "native stateDir must agree" {services.sabnzbd.stateDir = lib.mkForce "wrong";};

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.arr.sabnzbd.port = 70000;}]).config.nixstead.services.arr.sabnzbd.port).success;
  }
