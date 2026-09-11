{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixstead.services.pihole;
  syncCfg = cfg.dnsSync;
  homepageCredentialName = "homepage/piholeApiKey";
  homepageCredentialAvailable =
    builtins.hasAttr homepageCredentialName config.sops.secrets;
  credentialFile =
    if syncCfg.credentialFile != null
    then syncCfg.credentialFile
    else if homepageCredentialAvailable
    then config.sops.secrets.${homepageCredentialName}.path
    else null;

  registryFile = pkgs.writeText "nixstead-service-registry.json" (
    builtins.toJSON config.nixstead.serviceRegistry
  );
  hostFile = pkgs.writeText "nixstead-host.json" (builtins.toJSON config.nixstead.host);
  stateFile = "/var/lib/nixstead-pihole-dns-sync/managed-domains.json";
  deprecatedStateFile = "/var/lib/nixconfig-pihole-dns-sync/managed-domains.json";
  migrateStateProgram = pkgs.writeShellApplication {
    name = "nixstead-migrate-pihole-dns-sync-state";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      if [[ ! -e ${lib.escapeShellArg stateFile} && -f ${lib.escapeShellArg deprecatedStateFile} ]]; then
        install -m 0600 -o root -g root -- \
          ${lib.escapeShellArg deprecatedStateFile} \
          ${lib.escapeShellArg stateFile}
      fi
    '';
  };
  syncProgram = pkgs.writeShellApplication {
    name = "nixstead-sync-pihole-local-dns";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.jq
    ];
    text = builtins.readFile ../../scripts/sync-pihole-local-dns-from-nginx.sh;
  };
in {
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion =
            syncCfg.credentialFile
            == null
            || lib.hasPrefix "/" syncCfg.credentialFile;
          message = "nixstead.services.pihole.dnsSync.credentialFile must be an absolute runtime path.";
        }
      ];
    }

    (lib.mkIf (cfg.enable && syncCfg.enable && credentialFile != null) {
      systemd.services.nixstead-pihole-dns-sync = {
        description = "Reconcile registry-managed local DNS records in Pi-hole";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = [
          "network-online.target"
          "sops-install-secrets.service"
        ];
        restartTriggers = [registryFile hostFile];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          LoadCredential = "pihole-password:${credentialFile}";
          StateDirectory = "nixstead-pihole-dns-sync";
          StateDirectoryMode = "0700";
          ExecStartPre = "${migrateStateProgram}/bin/nixstead-migrate-pihole-dns-sync-state";
          ExecStart = lib.concatStringsSep " " [
            "${syncProgram}/bin/nixstead-sync-pihole-local-dns"
            "--registry-file ${registryFile}"
            "--host-file ${hostFile}"
            "--state-file ${stateFile}"
            "--prune-managed"
            "--skip-missing-credential"
            "--apply"
          ];

          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
        };
      };
    })
  ];
}
