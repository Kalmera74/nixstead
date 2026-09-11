{
  config,
  host,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  kiwixDataDir = config.nixstead.services.media.kiwix.paths.dataDir;
  kiwixLibraryPath = "${kiwixDataDir}/library.xml";
  cfg = config.nixstead.services.media;
in {
  config = lib.mkIf cfg.kiwix.enable {
    environment.systemPackages = with pkgs; [
      kiwix
      kiwix-tools
    ];

    systemd.services.kiwix-library-refresh = {
      description = "Refresh Kiwix library.xml from local .zim files";
      unitConfig.RequiresMountsFor = [kiwixDataDir];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "kiwix-library-refresh" ''
          set -euo pipefail

          base_path="${kiwixDataDir}"
          library_path="${kiwixLibraryPath}"

          if [[ ! -d "$base_path" ]]; then
            echo "Kiwix base path not found: $base_path"
            exit 1
          fi

          shopt -s nullglob
          zim_files=("$base_path"/*.zim)
          next_library="$(mktemp --tmpdir="$base_path" .library.xml.XXXXXX)"
          trap 'rm -f "$next_library"' EXIT

          if [[ "''${#zim_files[@]}" -eq 0 ]]; then
            echo "No .zim files found in $base_path"
            printf '%s\n' '<library version="20110515"></library>' > "$next_library"
          else
            # kiwix-manage initializes a missing library but rejects an
            # existing zero-byte file created by mktemp.
            rm -f "$next_library"
            for zim in "''${zim_files[@]}"; do
              ${pkgs.kiwix-tools}/bin/kiwix-manage "$next_library" add "$zim"
            done
          fi

          chmod 0644 "$next_library"
          mv -f "$next_library" "$library_path"
          trap - EXIT
        '';
      };
    };

    systemd.services.kiwix-serve = {
      description = "Kiwix offline library server";
      after = ["network-online.target" "kiwix-library-refresh.service"];
      wants = ["network-online.target" "kiwix-library-refresh.service"];
      requires = ["kiwix-library-refresh.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.kiwix-tools}/bin/kiwix-serve --monitorLibrary --library ${kiwixLibraryPath} --port ${toString config.nixstead.services.media.kiwix.port} --address ${serviceBindAddress "kiwix"}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
