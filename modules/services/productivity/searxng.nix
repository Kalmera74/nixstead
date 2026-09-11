{
  config,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity.searxng;
  dataDir = cfg.paths.dataDir;
  environmentFile = "${dataDir}/environment";
  bootstrapSecret = pkgs.writeShellScript "searxng-bootstrap-secret" ''
    set -euo pipefail

    install -d -m 0700 ${lib.escapeShellArg dataDir}
    if [ ! -s ${lib.escapeShellArg environmentFile} ]; then
      umask 077
      printf 'SEARX_SECRET_KEY=' > ${lib.escapeShellArg "${environmentFile}.tmp"}
      ${pkgs.openssl}/bin/openssl rand -hex 32 >> ${lib.escapeShellArg "${environmentFile}.tmp"}
      mv -f ${lib.escapeShellArg "${environmentFile}.tmp"} ${lib.escapeShellArg environmentFile}
    fi
  '';
in {
  config = lib.mkIf cfg.enable {
    services.searx = {
      enable = true;
      domain = cfg.domain;
      environmentFile = environmentFile;
      redisCreateLocally = true;
      settings = {
        general.instance_name = "SearXNG";
        server = {
          bind_address = serviceBindAddress "searxng";
          inherit (cfg) port;
          base_url = "https://${cfg.domain}/";
          secret_key = "$SEARX_SECRET_KEY";
          limiter = true;
          image_proxy = true;
        };
        search.safe_search = 0;
        ui.static_use_hash = true;
      };
    };

    systemd.services = {
      searx = {
        requires = ["redis-searx.service"];
        after = ["redis-searx.service"];
      };

      searxng-bootstrap-secret = {
        description = "Generate the SearXNG server secret";
        before = ["searx-init.service"];
        unitConfig.RequiresMountsFor = [dataDir];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = bootstrapSecret;
        };
      };

      searx-init = {
        requires = ["searxng-bootstrap-secret.service"];
        after = ["searxng-bootstrap-secret.service"];
      };
    };
  };
}
