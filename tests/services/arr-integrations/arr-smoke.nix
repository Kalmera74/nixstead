{
  pkgs,
  publicModules,
  phase,
}: let
  tools = import ../../../scripts/package.nix {inherit pkgs;};
  apps = ["sonarr" "radarr" "lidarr" "readarr" "bazarr" "prowlarr" "qbittorrent" "sabnzbd" "shelfmark"];
  workers = ["sonarr" "radarr" "lidarr" "readarr"];
  image = import ../swaparr/image.nix {inherit pkgs;};
in
  pkgs.testers.runNixOSTest {
    name = "nixstead-arr-smoke-${phase}";
    node.pkgsReadOnly = false;
    requiredFeatures.kvm = false;
    nodes.machine = {
      config,
      lib,
      ...
    }: {
      imports = [
        publicModules.arr
        (import ../../lib/secret-fixture.nix {
          inherit pkgs;
          generator = ./arr-smoke-secrets.py;
        })
      ];
      system.stateVersion = "26.05";
      nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "unrar";
      nixstead.services.arr =
        lib.genAttrs apps (_: {enable = true;})
        // {
          swaparr.enable = true;
          shelfmark = {
            enable = true;
            paths.ingestDir = "/data/ingest/books";
          };
          credentials = {
            enable = true;
            autoSync.enable = false;
          };
          storage = {
            root = "/data";
            manageDirectories = true;
            libraries.movies = null;
            libraries.music = null;
          };
          # One simple selected relationship exercises the shipped reconciler
          # and its journal without recreating the application API workflow.
          integrations.qbittorrentToSonarr.enable = true;
          integrations.storageToQbittorrent.enable = true;
        };
      sops.templates."readarr-api.env".content = ''
        READARR__AUTH__APIKEY=${config.sops.placeholder."swaparr/readarrApiKey"}
      '';
      services.readarr.environmentFiles = [config.sops.templates."readarr-api.env".path];
      systemd.timers.nixstead-arr-reconcile.timerConfig = {
        OnUnitInactiveSec = lib.mkForce "5s";
        RandomizedDelaySec = lib.mkForce "0";
      };
      services.qbittorrent.serverConfig = {
        BitTorrent = {
          "Session\\Interface" = "lo";
          "Session\\DHTEnabled" = false;
          "Session\\LSDEnabled" = false;
          "Session\\PeXEnabled" = false;
        };
        Preferences.Connection.UPnP = false;
      };
      virtualisation.oci-containers.containers = lib.genAttrs (map (app: "swaparr-${app}") workers) (_: {
        # The offline archive retains the tag from the exact production digest.
        image = lib.mkForce image.reference;
        environment.DRY_RUN = lib.mkForce "true";
        # Keep retries after concurrent application startup inside a smoke run.
        environment.SCAN_INTERVAL = lib.mkForce "5s";
      });
      systemd.services.arr-smoke-images = {
        requires = ["docker.service"];
        after = ["docker.service"];
        # Bring up Docker before the concurrent native database migrations;
        # containerd has a short internal startup deadline under VM contention.
        before = map (app: "docker-swaparr-${app}.service") workers ++ map (app: "${app}.service") apps;
        requiredBy = map (app: "docker-swaparr-${app}.service") workers;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [pkgs.docker];
        script = ''
          if ! docker image inspect ${lib.escapeShellArg image.reference} >/dev/null 2>&1; then
            docker load --input ${image.archive}
          fi
        '';
      };
      environment.etc."backup-registry.json".text = builtins.toJSON (
        lib.getAttrs (apps ++ ["arr-integrations"]) config.nixstead.serviceRegistry
      );
      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
        pkgs.borgbackup
        tools.commands.backup-service-configs
        tools.commands.restore-service-configs
      ];
      virtualisation = {
        memorySize = 4096;
        cores = 2;
        diskSize = 12288;
        fileSystems."/data" = {
          device = "tmpfs";
          fsType = "tmpfs";
        };
      };
    };
    testScript = ''
      import runpy
      ServiceScenario = runpy.run_path(${builtins.toJSON "${../../lib/service_scenario.py}"})["ServiceScenario"]
      phase = ${builtins.toJSON phase}
      start_all()
      ${builtins.readFile ./arr-smoke-scenario.py}
    '';
  }
