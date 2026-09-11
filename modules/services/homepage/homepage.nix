{
  config,
  host,
  lib,
  secretPlaceholder,
  serviceBindAddress,
  serviceOptionFromRegistry,
  ...
}: let
  cfg = config.nixstead.services.homepage;
  homepageHosts =
    [config.nixstead.services.homepage.domain]
    ++ lib.optional (config.nixstead.host.network.lan != null) "${config.nixstead.host.network.lan}:${toString config.nixstead.services.homepage.port}"
    ++ lib.optional (config.nixstead.host.network.tailscale != null) config.nixstead.host.network.tailscale;

  homepageRegistry =
    lib.filterAttrs (
      id: entry:
        entry.enabled
        && entry.homepage != null
        && (entry.homepage.widget or null) != null
        && !lib.elem id cfg.disabledWidgets
    )
    config.nixstead.serviceRegistry;
  homepageEntries = lib.attrValues homepageRegistry;
  homepageSecretNames = lib.unique (lib.concatMap (
      entry:
        lib.attrValues (entry.homepage.widget.secrets or {})
    )
    homepageEntries);
  homepageSecrets = lib.genAttrs homepageSecretNames (name: "{{HOMEPAGE_VAR_${lib.toUpper name}}}");
  sharedEntries = lib.filterAttrs (id: entry: (config.nixstead.services.arr.credentials.enable or false) && entry.api != null || id == "qbittorrent") homepageRegistry;
  sharedNames = lib.concatMap (entry: lib.attrValues entry.homepage.widget.secrets) (lib.attrValues sharedEntries);
  manualNames = lib.filter (name: !lib.elem name sharedNames) homepageSecretNames;
  canonicalNames = lib.listToAttrs (lib.concatMap (entry:
    lib.optional (entry.api != null) {
      name = entry.homepage.widget.secrets.key;
      value = entry.api.sopsSecret;
    })
  homepageEntries);
  secretName = name: canonicalNames.${name} or "homepage/${name}";

  homepageServices =
    (import ./services-network.nix {inherit host homepageSecrets;})
    ++ (import ./services-registry.nix {inherit config homepageSecrets lib;})
    ++ (import ./shortcuts.nix {
      inherit lib;
      inherit (cfg) shortcuts;
    });
in {
  options.nixstead.services.homepage = serviceOptionFromRegistry "homepage" {
    extraOptions = {
      shortcuts = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Shortcut title shown on the Homepage dashboard.";
            };
            href = lib.mkOption {
              type = lib.types.str;
              description = "URL opened by the shortcut.";
            };
            icon = lib.mkOption {
              type = lib.types.str;
              default = "mdi-web";
              description = "Homepage icon name, direct icon URL, or PNG filename from the shared dashboard-icons catalog.";
            };
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Short description shown below the shortcut title.";
            };
          };
        });
        default = [];
        description = "Host-specific shortcuts rendered in the Homepage Shortcuts section.";
      };
      disabledWidgets = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = [];
        example = ["grafana"];
        description = "Registry service IDs whose Homepage cards remain visible but whose optional widgets and widget secrets are disabled.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = lib.genAttrs (map secretName manualNames) (
      name:
        lib.optionalAttrs (
          name
          == "homepage/piholeApiKey"
          && config.nixstead.services.pihole.dnsSync.enable
        ) {
          restartUnits = ["nixstead-pihole-dns-sync.service"];
        }
    );

    sops.templates."homepage.env" = lib.mkIf (manualNames != []) {
      content =
        lib.concatMapStringsSep "\n" (
          name: "HOMEPAGE_VAR_${lib.toUpper name}=${secretPlaceholder (secretName name)}"
        )
        manualNames;
      restartUnits = ["homepage-dashboard.service"];
    };

    services.homepage-dashboard = {
      enable = true;
      environmentFiles =
        lib.optional (manualNames != []) config.sops.templates."homepage.env".path
        ++ map (id: "/run/nixstead-credentials/${id}/homepage.env") (lib.attrNames sharedEntries);
      listenPort = config.nixstead.services.homepage.port;
      openFirewall = false;
      allowedHosts = lib.concatStringsSep "," homepageHosts;

      widgets = [
        {
          search = {
            provider = "custom";
            url = "https://search.nixos.org/packages?query=";
            target = "_blank";
            # keep provider available for the overlay search that opens when
            # typing, but don't render or focus the top-page search input.
            focus = false;
          };
        }
      ];

      customCSS = ''
        #information-widgets {
          margin-top: 0 !important;
          padding-top: 0 !important;
        }

        .container {
          padding-top: 0 !important;
        }
      '';

      customJS = ''
        (() => {
          const updateSearchPlaceholderAndHideTop = () => {
            const searchInput =
              document.querySelector("#information-widgets input[placeholder]") ??
              document.querySelector("#information-widgets input[type='search']") ??
              document.querySelector("#information-widgets input[type='text']");

            if (!searchInput) {
              return;
            }

            // Ensure the placeholder text remains correct for accessibility
            if (searchInput.getAttribute("placeholder") != "Search Nixpkgs...") {
              searchInput.setAttribute("placeholder", "Search Nixpkgs...");
            }

            // Hide the top-page search input so the page stays clean, but do not
            // remove the provider from the widgets config — the overlay search
            // that appears when typing will still use the configured provider.
            try {
              const container = searchInput.closest('.widget') || searchInput.parentElement;
              if (container) {
                container.style.display = 'none';
                container.style.visibility = 'hidden';
                // shrink to avoid layout gaps
                container.style.width = '0px';
                container.style.height = '0px';
                container.style.overflow = 'hidden';
              }
            } catch (e) {
              // ignore errors in older/unknown DOMs
            }
          };

          document.addEventListener("DOMContentLoaded", updateSearchPlaceholderAndHideTop);
          window.addEventListener("load", updateSearchPlaceholderAndHideTop);
          setInterval(updateSearchPlaceholderAndHideTop, 1000);
        })();
      '';

      services = homepageServices;
      settings = import ./settings.nix {inherit host;};
    };

    systemd.services.homepage-dashboard.environment.HOSTNAME = serviceBindAddress "homepage";
  };
}
