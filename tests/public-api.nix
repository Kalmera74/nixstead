{
  nixpkgs,
  lib,
  publicModules,
  system,
}: let
  pkgs = import nixpkgs {inherit system;};
  registry = import ../modules/services/registry.nix;
  syntheticHardware = {
    boot.loader.grub.devices = ["/dev/vda"];
    fileSystems."/" = {
      device = "/dev/vda1";
      fsType = "ext4";
    };
  };
  mkSystem = modules:
    nixpkgs.lib.nixosSystem {
      inherit system;
      modules =
        (
          if builtins.isList modules
          then modules
          else [modules]
        )
        ++ [
          {
            imports = [syntheticHardware];
            # Public closure tests use the pinned unstable baseline and a new
            # host state version. Existing hosts keep their historical value.
            system.stateVersion = "26.05";
            nixstead.secrets = {
              enable = true;
              sopsFile = ../secrets/test.yaml;
            };
          }
        ];
    };
  publicClosureModules = import ./fixtures/public-closures.nix {inherit publicModules;};
  closureDrvPath = modules:
    builtins.unsafeDiscardStringContext
    (mkSystem modules).config.system.build.toplevel.drvPath;
  publicClosureDrvPaths = lib.mapAttrs (_: closureDrvPath) publicClosureModules;
  templateClosureDrvPath = closureDrvPath [publicModules.default ../templates/host/configuration.nix];
  hasFailedAssertion = modules: message:
    lib.any (
      item: !item.assertion && lib.hasInfix message item.message
    )
    (mkSystem modules).config.assertions;
  setupIds = lib.filter (
    id: registry.${id}.setup != null && registry.${id}.setup.presetControlled
  ) (lib.attrNames registry);
  expectedPresetIds = preset:
    lib.filter (id: lib.elem preset registry.${id}.setup.presets) setupIds;
  enabledPresetIds = module: let
    resolved = (mkSystem module).config.nixstead.serviceRegistry;
  in
    lib.filter (id: resolved.${id}.enabled) setupIds;
  presetParity = {
    media-starter = expectedPresetIds "media-starter" == enabledPresetIds [publicModules.default {nixstead.preset = "media-starter";}];
    minimal = expectedPresetIds "minimal" == enabledPresetIds publicModules.profile-minimal;
    media-server = expectedPresetIds "media-server" == enabledPresetIds publicModules.profile-media-server;
    development = expectedPresetIds "development" == enabledPresetIds publicModules.profile-development;
    full = expectedPresetIds "full" == enabledPresetIds publicModules.profile-full;
  };
  customPortSystem = mkSystem [
    publicModules.default
    ./fixtures/custom-service-options.nix
  ];
  externalOllamaSystem = mkSystem [
    publicModules.localai
    {
      nixstead.services.localai = {
        ollama.enable = false;
        openwebui = {
          enable = true;
          ollamaUrl = "http://ollama.example.test:11434";
        };
      };
    }
  ];
  customCaSystem = mkSystem [
    publicModules.default
    {
      nixstead.host = {
        hostName = "certificate-test";
        user = {
          enable = true;
          name = "certificate-test";
          uid = 1234;
        };
      };
      nixstead.services.nginx = {
        enable = true;
        ca = {
          certificateFile = "/run/credentials/nginx-ca.crt";
          privateKeyFile = "/run/credentials/nginx-ca.key";
          renewBeforeDays = 45;
        };
      };
    }
  ];
  apiParity = import ./api-parity.nix {
    inherit
      lib
      registry
      mkSystem
      closureDrvPath
      hasFailedAssertion
      publicModules
      publicClosureModules
      customPortSystem
      externalOllamaSystem
      customCaSystem
      ;
    templateFlake = ../templates/host/flake.nix;
    templateConfiguration = ../templates/host/configuration.nix;
  };
  report = {
    baseHostName = (mkSystem publicModules.base).config.nixstead.host.hostName;
    arrPort = (mkSystem publicModules.arr).config.nixstead.services.arr.radarr.port;
    fullPresetEnablesNextcloud = (mkSystem publicModules.profile-full).config.nixstead.services.productivity.nextcloud.enable;
    minimalPresetEnablesTailscale = (mkSystem publicModules.profile-minimal).config.nixstead.services.tailscale.enable;
    templateHostName = (mkSystem [publicModules.default ../templates/host/configuration.nix]).config.nixstead.host.hostName;
    publicClosures = publicClosureDrvPaths // {host-template = templateClosureDrvPath;};
    registrySize = lib.length (lib.attrNames registry);
    inherit apiParity presetParity arrParity wireguardParity reliabilityParity;
  };
  reliabilityParity = import ./reliability-options.nix {inherit lib mkSystem hasFailedAssertion publicModules;};
  arrParity = import ./arr-options.nix {inherit lib mkSystem hasFailedAssertion publicModules;};
  wireguardParity = import ./wireguard-options.nix {inherit lib mkSystem hasFailedAssertion publicModules;};
  failures = lib.concatLists (lib.mapAttrsToList (group: assertions:
    map (name: "${group}.${name}") (lib.attrNames (lib.filterAttrs (_: passed: !passed) assertions))) {
    inherit presetParity apiParity arrParity wireguardParity reliabilityParity;
  });
in
  assert lib.assertMsg (failures == []) "Public module API checks failed: ${lib.concatStringsSep ", " failures}";
    pkgs.writeText "nixstead-public-api-check.json" (builtins.toJSON report)
