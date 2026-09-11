{
  config,
  host,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixstead.services.productivity;
  nextcloudDataDir =
    if cfg.nextcloud.paths.dataDir != null
    then cfg.nextcloud.paths.dataDir
    else config.services.nextcloud.datadir;
  generatedAdminPasswordFile = "${config.services.nextcloud.home}/nixos-nextcloud-admin-pass";
  generateAdminPassword = cfg.nextcloud.adminPasswordFile == null;
  nextcloudAdminPassFile =
    if generateAdminPassword
    then generatedAdminPasswordFile
    else cfg.nextcloud.adminPasswordFile;

  nextcloudGenerateAdminPassScript = pkgs.writeShellScriptBin "nextcloud-generate-admin-pass" ''
    set -euo pipefail

    pass_file="${nextcloudAdminPassFile}"

    install -d -m 750 -o nextcloud -g nextcloud "$(dirname "$pass_file")"
    umask 077
    if [ ! -s "$pass_file" ]; then
      temporary="$(mktemp "$pass_file.XXXXXX")"
      trap 'rm -f -- "$temporary"' EXIT
      ${pkgs.openssl}/bin/openssl rand -hex 24 > "$temporary"
      chown nextcloud:nextcloud "$temporary"
      mv -f -- "$temporary" "$pass_file"
    fi
    # Repair files left root-owned by an interrupted or older activation.
    chown nextcloud:nextcloud "$pass_file"
    chmod 0600 "$pass_file"
  '';
in {
  config = lib.mkIf cfg.nextcloud.enable {
    services.nextcloud =
      {
        enable = true;
        hostName = config.nixstead.services.productivity.nextcloud.domain;
        https = false;
        config = {
          adminuser = "admin";
          adminpassFile = nextcloudAdminPassFile;
          dbtype = "sqlite";
        };
        settings = {
          trusted_domains =
            [config.nixstead.services.productivity.nextcloud.domain]
            ++ lib.optional (config.nixstead.host.network.lan != null) config.nixstead.host.network.lan;
        };
      }
      // lib.optionalAttrs (cfg.nextcloud.paths.dataDir != null) {
        datadir = cfg.nextcloud.paths.dataDir;
      };

    environment.systemPackages = lib.optional generateAdminPassword nextcloudGenerateAdminPassScript;

    system.activationScripts.nextcloud-admin-pass = lib.mkIf generateAdminPassword {
      deps = [
        "users"
        "groups"
      ];
      text = ''
        ${nextcloudGenerateAdminPassScript}/bin/nextcloud-generate-admin-pass
      '';
    };

    systemd.services.nextcloud-setup.unitConfig.RequiresMountsFor = [nextcloudDataDir nextcloudAdminPassFile];
    systemd.services."phpfpm-nextcloud".unitConfig.RequiresMountsFor = [nextcloudDataDir];

    services.nginx.virtualHosts.${config.nixstead.services.productivity.nextcloud.domain}.listen = [
      {
        addr = "127.0.0.1";
        port = config.nixstead.services.productivity.nextcloud.port;
      }
    ];
  };
}
