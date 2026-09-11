{
  lib,
  serviceOptionFromRegistry,
  ...
}: {
  imports = [./pihole-dns-sync.nix];

  options.nixstead.services = {
    pihole = serviceOptionFromRegistry "pihole" {
      extraOptions.dnsSync = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Explicitly opt in to reconciling registry-managed local DNS
                records in Pi-hole when the deployed service set changes.
              '';
            };

            credentialFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "/run/secrets/pihole-application-password";
              description = ''
                Optional absolute runtime path containing a Pi-hole 6 password
                or application password. When unset, the Homepage
                homepage/piholeApiKey SOPS secret is reused when available.
              '';
            };
          };
        };
        default = {};
        description = "Automatic Pi-hole local DNS synchronization.";
      };
    };
    proxmox = serviceOptionFromRegistry "proxmox" {};
    truenas = serviceOptionFromRegistry "truenas" {};
  };
}
