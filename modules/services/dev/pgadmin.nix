{
  config,
  host,
  lib,
  pkgs,
  secretPath,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev;
in {
  config = lib.mkIf cfg.pgadmin.enable {
    assertions = [
      {
        assertion =
          config.services.pgadmin.settings.DATA_DIR
          == "/var/lib/pgadmin"
          && config.services.pgadmin.settings.CONFIG_DATABASE_URI == ""
          && lib.all (path: builtins.isString path && lib.hasPrefix "/var/lib/pgadmin/" path && !(lib.elem ".." (lib.splitString "/" path)))
          [config.services.pgadmin.settings.SQLITE_PATH config.services.pgadmin.settings.STORAGE_DIR];
        message = "Nixstead pgAdmin recovery requires local SQLite, DATA_DIR = /var/lib/pgadmin and SQLITE_PATH/STORAGE_DIR below that directory.";
      }
    ];
    sops.secrets."devdb/pgadmin/initialPassword" = {
      restartUnits = ["pgadmin.service"];
    };

    # The native module needs PostgreSQL client binaries even for remote-only
    # administration; selecting pgAdmin must not require enabling a local server.
    services.postgresql.package = lib.mkOverride 1100 pkgs.postgresql;

    services.pgadmin = {
      enable = true;
      initialEmail = cfg.pgadmin.initialEmail;
      initialPasswordFile = secretPath "devdb/pgadmin/initialPassword";
      port = config.nixstead.services.dev.pgadmin.port;
      openFirewall = false;
      settings = {
        DEFAULT_SERVER = serviceBindAddress "pgadmin";
        # Preserve the existing local-only bootstrap email with the native
        # validator, which otherwise rejects special-use .local domains.
        ALLOW_SPECIAL_EMAIL_DOMAINS = lib.mkDefault ["local"];
        DATA_DIR = lib.mkDefault "/var/lib/pgadmin";
        CONFIG_DATABASE_URI = lib.mkDefault "";
        SQLITE_PATH = lib.mkDefault "/var/lib/pgadmin/pgadmin4.db";
        STORAGE_DIR = lib.mkDefault "/var/lib/pgadmin/storage";
      };
    };
  };
}
