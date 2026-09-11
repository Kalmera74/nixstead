{
  config,
  lib,
  secretPath,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.arr.sabnzbd;
  shared = config.nixstead.services.arr.credentials.enable;
in {
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "/var/lib/" cfg.paths.dataDir && !lib.hasPrefix "/var/lib/private" cfg.paths.dataDir && lib.all (part: part != "" && part != "." && part != "..") (lib.tail (lib.splitString "/" cfg.paths.dataDir));
        message = "SABnzbd state must be a normalized directory below /var/lib, outside private dynamic-user storage.";
      }
      {
        assertion = "/var/lib/${config.services.sabnzbd.stateDir}" == cfg.paths.dataDir;
        message = "SABnzbd native stateDir must agree with its registry path.";
      }
    ];
    services.sabnzbd = {
      enable = true;
      configFile = null;
      stateDir = lib.removePrefix "/var/lib/" cfg.paths.dataDir;
      group = config.nixstead.host.groups.media;
      openFirewall = false;
      allowConfigWrite = true;
      settings.misc = {
        host = serviceBindAddress "sabnzbd";
        port = cfg.port;
        # API authentication is always required, including loopback consumers.
        api_warnings = true;
        inet_exposure = 0;
      };
      secretFiles = lib.optional (cfg.secretFile != null) "/run/credentials/sabnzbd.service/settings.ini" ++ lib.optional shared "/run/credentials/sabnzbd.service/nixstead.ini";
    };
    systemd.services.sabnzbd.serviceConfig = {
      StateDirectoryMode = "0700";
      UMask = lib.mkForce "0002";
      LoadCredential =
        lib.optional shared "nixstead.ini:/run/nixstead-credentials/sabnzbd/native.ini"
        ++ lib.optional (cfg.secretFile != null) "settings.ini:${cfg.secretFile}";
    };
  };
}
