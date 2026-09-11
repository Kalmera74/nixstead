{
  config,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.media;
  native = config.services.immich;
  serviceUser = native.user;
  sqlIdentifier = value: "\"${lib.replaceStrings ["\""] ["\"\""] value}\"";
  databaseOwnership = pkgs.writeText "immich-database-owner.sql" ''
    ALTER DATABASE ${sqlIdentifier native.database.name} OWNER TO ${sqlIdentifier native.database.user};
  '';
in {
  config = lib.mkIf cfg.immich.enable {
    services.immich =
      {
        enable = true;
        group = lib.mkDefault config.nixstead.host.groups.media;
        host = serviceBindAddress "immich";
        port = cfg.immich.port;
        database = {
          # Provision the named database/role below. Upstream createDB assumes
          # identical names, which is not required for an existing installation.
          createDB = false;
          user = lib.mkDefault serviceUser;
          host = lib.mkDefault "/run/postgresql";
        };
      }
      // lib.optionalAttrs (cfg.immich.paths.mediaLocation != null) {
        mediaLocation = cfg.immich.paths.mediaLocation;
      };

    systemd.tmpfiles.rules = let
      mediaLocation = config.services.immich.mediaLocation;
    in [
      # Upstream's `e` rule adjusts an existing root but cannot create a custom
      # one. Create it before the children so implicit parents are not root-owned.
      "d ${mediaLocation} 0700 ${serviceUser} ${native.group} -"
      "d ${mediaLocation}/upload 0775 ${serviceUser} ${native.group} -"
      "d ${mediaLocation}/thumbs 0775 ${serviceUser} ${native.group} -"
      "d ${mediaLocation}/backups 0775 ${serviceUser} ${native.group} -"
      "d ${mediaLocation}/library 0775 ${serviceUser} ${native.group} -"
      "d ${mediaLocation}/profile 0775 ${serviceUser} ${native.group} -"
      "d ${mediaLocation}/encoded-video 0775 ${serviceUser} ${native.group} -"
      "f ${mediaLocation}/upload/.immich 0664 ${serviceUser} ${native.group} -"
      "f ${mediaLocation}/thumbs/.immich 0664 ${serviceUser} ${native.group} -"
      "f ${mediaLocation}/backups/.immich 0664 ${serviceUser} ${native.group} -"
      "f ${mediaLocation}/library/.immich 0664 ${serviceUser} ${native.group} -"
      "f ${mediaLocation}/profile/.immich 0664 ${serviceUser} ${native.group} -"
      "f ${mediaLocation}/encoded-video/.immich 0664 ${serviceUser} ${native.group} -"
    ];

    assertions = [
      {
        assertion = builtins.hasAttr serviceUser config.users.users;
        message = "The configured Immich user must exist; custom services.immich.user accounts must be declared by the host.";
      }
    ];
    services.postgresql = lib.mkIf native.database.enable {
      ensureDatabases = [native.database.name];
      ensureUsers = [
        {
          name = native.database.user;
          ensureClauses.login = true;
        }
      ];
    };
    systemd.services.postgresql-setup.serviceConfig.ExecStartPost = lib.mkIf native.database.enable (lib.mkAfter [
      "${config.services.postgresql.package}/bin/psql --set ON_ERROR_STOP=1 --dbname=${lib.escapeShellArg native.database.name} --file=${databaseOwnership}"
    ]);
    systemd.services.immich-server.unitConfig.RequiresMountsFor = [config.services.immich.mediaLocation];
    systemd.services.immich-machine-learning = lib.mkIf config.services.immich.machine-learning.enable {
      unitConfig.RequiresMountsFor = [config.services.immich.mediaLocation];
      # Gunicorn's control socket must stay outside the protected user home.
      environment.XDG_RUNTIME_DIR = "/run/immich-machine-learning";
      serviceConfig = {
        RuntimeDirectory = "immich-machine-learning";
        RuntimeDirectoryMode = "0700";
      };
    };
  };
}
