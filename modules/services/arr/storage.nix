{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  cfg = config.nixstead.services.arr;
  storage = cfg.storage;
  inherit (lib) mkOption types;
  pathType = types.addCheck types.str (path:
    lib.hasPrefix "/" path
    && path != "/"
    && lib.all (part: part != "" && part != "." && part != "..") (lib.tail (lib.splitString "/" path)));
  pathOption = default: description:
    mkOption {
      type = types.nullOr pathType;
      inherit default description;
    };
  under = root: path: root != null && path != null && (root == path || lib.hasPrefix "${root}/" path);
  append = root: suffix:
    if root == null
    then null
    else "${root}/${suffix}";
  selectedLibraries = lib.filterAttrs (name: path:
    path
    != null
    && cfg.${
      {
        tv = "sonarr";
        movies = "radarr";
        music = "lidarr";
      }.${
        name
      }
    }.enable)
  storage.libraries;
  usenet = lib.optionals cfg.sabnzbd.enable (lib.filter (path: path != null) [storage.usenet.root storage.usenet.incomplete storage.usenet.complete]);
  torrents = lib.filter (path: path != null) [storage.torrents.root storage.torrents.incomplete];
  downloads = usenet ++ torrents;
  linksFor = library: lib.optionals (library != null) (map (source: [source library]) (lib.filter (path: path != null) ([storage.torrents.root] ++ lib.optional cfg.sabnzbd.enable storage.usenet.complete)));
  libraries = lib.attrValues selectedLibraries;
  paths = lib.unique (lib.concatMap (writer: writer.paths) (lib.attrValues writers));
  mountsFor = selectedPaths:
    lib.unique (storage.requiredMounts
      ++ lib.filter (mount:
        mount != "/" && lib.any (under mount) selectedPaths) (lib.attrNames config.fileSystems));
  mounts = mountsFor paths;
  mountUnitsFor = selectedPaths: map (mount: "${utils.escapeSystemdPath mount}.mount") (mountsFor selectedPaths);
  configFile = name: selectedPaths: links:
    pkgs.writeText "arr-storage-${name}.json" (builtins.toJSON {
      paths = selectedPaths;
      mounts = mountsFor selectedPaths;
      inherit links;
      group = config.nixstead.host.groups.media;
      manageExisting = storage.manageExistingDirectories;
      inherit (storage.validation) hardlinks;
    });
  run = file: "${pkgs.python3}/bin/python3 ${./storage.py} ${file}";
  writers = lib.filterAttrs (_: value: value.enable && value.paths != []) {
    shelfmark = {
      inherit (cfg.shelfmark) enable;
      paths = lib.optional (cfg.shelfmark.paths.ingestDir != null) cfg.shelfmark.paths.ingestDir ++ lib.optionals cfg.shelfmark.integrations.qbittorrent torrents;
      links = [];
    };
    sabnzbd = {
      inherit (cfg.sabnzbd) enable;
      paths = usenet;
      links = [];
    };
    qbittorrent = {
      inherit (cfg.qbittorrent) enable;
      paths = torrents;
      links = [];
    };
    sonarr = {
      inherit (cfg.sonarr) enable;
      paths = lib.optional (storage.libraries.tv != null) storage.libraries.tv ++ downloads;
      links = linksFor storage.libraries.tv;
    };
    radarr = {
      inherit (cfg.radarr) enable;
      paths = lib.optional (storage.libraries.movies != null) storage.libraries.movies ++ downloads;
      links = linksFor storage.libraries.movies;
    };
    lidarr = {
      inherit (cfg.lidarr) enable;
      paths = lib.optional (storage.libraries.music != null) storage.libraries.music ++ downloads;
      links = linksFor storage.libraries.music;
    };
    bazarr = {
      inherit (cfg.bazarr) enable;
      paths = libraries;
      links = [];
    };
  };
in {
  options.nixstead.services.arr.storage = {
    root = pathOption null "Optional common media root. Defaults below this root are overrideable; an unconfigured ARR stack creates no media directories.";
    manageDirectories = mkOption {
      type = types.bool;
      default = false;
      description = "Create missing selected media directories with the media group and setgid permissions.";
    };
    manageExistingDirectories = mkOption {
      type = types.bool;
      default = false;
      description = "Explicitly set group write and setgid on selected existing directories; never recurse into existing libraries.";
    };
    requiredMounts = mkOption {
      type = types.listOf pathType;
      default = [];
      description = "Additional filesystem mount points which must be mounted before creating or writing media. Declared fileSystems ancestors are detected automatically.";
    };
    torrents = {
      root = pathOption (append storage.root "torrents") "Torrent download root.";
      incomplete = pathOption (append storage.torrents.root "incomplete") "Incomplete torrent directory.";
    };
    usenet = {
      root = pathOption (append storage.root "usenet") "Optional Usenet download root; used only when SABnzbd is selected.";
      incomplete = pathOption (append storage.usenet.root "incomplete") "Incomplete Usenet downloads.";
      complete = pathOption (append storage.usenet.root "complete") "Completed Usenet downloads, with selected application categories below.";
    };
    libraries = {
      tv = pathOption (append storage.root "media/tv") "Selected Sonarr library root.";
      movies = pathOption (append storage.root "media/movies") "Selected Radarr library root.";
      music = pathOption (append storage.root "media/music") "Selected Lidarr library root.";
    };
    validation = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run disposable CRUD and optional hardlink probes as each media-writing service, inside its startup sandbox.";
      };
      hardlinks = mkOption {
        type = types.enum ["disabled" "warn" "require"];
        default = "warn";
        description = "Whether failed actual hardlink probes are ignored, reported, or prevent service startup.";
      };
    };
  };

  config = lib.mkMerge [
    {
      services.sabnzbd.settings.misc = lib.mkIf cfg.sabnzbd.enable (lib.optionalAttrs (storage.usenet.incomplete != null) {download_dir = lib.mkDefault storage.usenet.incomplete;} // lib.optionalAttrs (storage.usenet.complete != null) {complete_dir = lib.mkDefault storage.usenet.complete;});
      nixstead.services.arr.qbittorrent.paths = {
        savePath = lib.mkDefault storage.torrents.root;
        tempPath = lib.mkDefault storage.torrents.incomplete;
      };
      assertions = [
        {
          assertion = lib.all (library: !lib.any (download: under download library || under library download) downloads) libraries;
          message = "ARR storage download and library trees must be separate.";
        }
        {
          assertion = storage.torrents.incomplete == null || under storage.torrents.root storage.torrents.incomplete;
          message = "ARR incomplete downloads must be contained in storage.torrents.root.";
        }
        {
          assertion = lib.all (path: path == null || under storage.usenet.root path) [storage.usenet.incomplete storage.usenet.complete];
          message = "Usenet paths must be contained in storage.usenet.root.";
        }
        {
          assertion = storage.usenet.incomplete == null || storage.usenet.complete == null || !(under storage.usenet.incomplete storage.usenet.complete || under storage.usenet.complete storage.usenet.incomplete);
          message = "Usenet incomplete and complete trees must be separate.";
        }
        {
          assertion = !storage.manageExistingDirectories || storage.manageDirectories;
          message = "ARR manageExistingDirectories requires manageDirectories.";
        }
        {
          assertion = lib.all (path: !(lib.hasPrefix "/mnt/" path || lib.hasPrefix "/media/" path) || lib.any (mount: under mount path) mounts) paths;
          message = "ARR paths under /mnt or /media require a declared fileSystems mount or storage.requiredMounts guard.";
        }
      ];
    }
    (lib.mkIf (paths != []) {
      systemd.services =
        lib.mapAttrs (name: writer: {
          after = mountUnitsFor writer.paths ++ lib.optional storage.manageDirectories "nixstead-arr-directories.service";
          bindsTo = mountUnitsFor writer.paths;
          requires = lib.optional storage.manageDirectories "nixstead-arr-directories.service";
          unitConfig.RequiresMountsFor = writer.paths ++ mountsFor writer.paths;
          serviceConfig = {
            UMask = lib.mkForce "0002";
            StateDirectoryMode = "0700";
            # Separate writable bind mounts cause EXDEV even on the same device.
            # Keep a declared common root as one mount inside the service sandbox.
            ReadWritePaths =
              if storage.root != null && lib.all (under storage.root) writer.paths
              then [storage.root]
              else writer.paths;
            ExecStartPre = lib.mkAfter [(run (configFile name writer.paths writer.links) + lib.optionalString (!storage.validation.enable) " --guard-only")];
          };
        })
        writers
        // lib.optionalAttrs storage.manageDirectories {
          nixstead-arr-directories = {
            description = "Create explicitly selected ARR media directories after mounts";
            unitConfig.RequiresMountsFor = paths ++ mounts;
            after = mountUnitsFor paths;
            bindsTo = mountUnitsFor paths;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              UMask = "0002";
              ExecStart = run (configFile "directories" paths []) + " --create";
            };
          };
        };
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "nixstead-storage-diagnostic";
          runtimeInputs = [pkgs.util-linux pkgs.systemd];
          text = let
            diagnostic = pkgs.writeText "arr-storage-diagnostic.json" (builtins.toJSON {
              python = "${pkgs.python3}/bin/python3";
              probe = "${./storage.py}";
              services = lib.mapAttrs (name: writer: configFile name writer.paths writer.links) writers;
            });
          in ''
            exec ${pkgs.python3}/bin/python3 ${./storage_diagnostic.py} ${diagnostic} "$@"
          '';
        })
      ];
    })
  ];
}
