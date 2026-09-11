{
  config,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.media;
  tokenKeyFile = config.services.kavita.tokenKeyFile;
  tokenKeyDirectory = builtins.dirOf tokenKeyFile;

  generateTokenKey = pkgs.writeShellScript "kavita-generate-token-key" ''
    set -euo pipefail

    token_key_file=${lib.escapeShellArg tokenKeyFile}
    token_key_directory=${lib.escapeShellArg tokenKeyDirectory}

    if [ -s "$token_key_file" ]; then
      exit 0
    fi

    # A custom key may live in an existing shared directory such as /run.
    # Preserve that directory's permissions; the generated key itself is 0600.
    if [ ! -d "$token_key_directory" ]; then
      install -d -m 0750 "$token_key_directory"
    fi

    temporary_key="$(mktemp "$token_key_directory/.kavita-token-key.XXXXXX")"
    trap 'rm -f "$temporary_key"' EXIT

    umask 077
    head -c 64 /dev/urandom | base64 --wrap=0 > "$temporary_key"
    chmod 0600 "$temporary_key"
    mv -f "$temporary_key" "$token_key_file"
    trap - EXIT
  '';
in {
  config = lib.mkIf cfg.kavita.enable {
    services.kavita =
      {
        enable = true;
        tokenKeyFile = cfg.kavita.tokenKeyFile;
        settings = {
          IpAddresses = serviceBindAddress "kavita";
          Port = cfg.kavita.port;
        };
      }
      // lib.optionalAttrs (cfg.kavita.paths.dataDir != null) {
        dataDir = cfg.kavita.paths.dataDir;
      };

    systemd.services = {
      kavita-token-key = {
        description = "Generate the Kavita token key when missing";
        before = ["kavita.service"];
        requiredBy = ["kavita.service"];
        path = [pkgs.coreutils];
        unitConfig.RequiresMountsFor = [tokenKeyDirectory];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = generateTokenKey;
        };
      };

      kavita = {
        requires = ["kavita-token-key.service"];
        after = ["kavita-token-key.service"];
        unitConfig.RequiresMountsFor = lib.unique [
          tokenKeyDirectory
          config.services.kavita.dataDir
        ];
      };
    };
  };
}
