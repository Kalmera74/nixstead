{
  description = "Nixstead: a registry-driven NixOS platform for self-hosted infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement/ce8949125b698406810ea71a8bd7b567d9a0b09f";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    sops-nix,
    vpn-confinement,
    ...
  }: let
    inherit (nixpkgs) lib;

    supportedSystems = ["x86_64-linux" "aarch64-linux"];

    secretModules = [
      sops-nix.nixosModules.sops
      ./modules/secrets/sops.nix
    ];

    withSecrets = module: {
      imports = secretModules ++ [module];
    };

    withVpn = module: {
      imports = [vpn-confinement.nixosModules.default module];
    };

    withCore = module: {
      imports =
        [
          ./modules/core/options.nix
          ./modules/services/container-runtime.nix
          ./modules/services/registry-integrations.nix
        ]
        ++ secretModules ++ [module];
    };

    completePreset = preset: {
      imports = [publicModules.default];
      nixstead.preset = preset;
    };

    publicModules = {
      default = withSecrets (withVpn ./modules/default.nix);
      base = withSecrets ./modules/base.nix;
      secrets = {
        imports = [./modules/core/options.nix] ++ secretModules;
      };
      tools = {
        imports =
          [./modules/core/options.nix]
          ++ secretModules
          ++ [./modules/system/tools.nix];
      };
      services = withCore (withVpn ./modules/services/services.nix);

      arr = withCore (withVpn ./modules/services/arr/arr.nix);
      media = withCore ./modules/services/media/media.nix;
      dev = withCore ./modules/services/dev/dev.nix;
      localai = withCore ./modules/services/localai/localai.nix;
      productivity = withCore ./modules/services/productivity/productivity.nix;
      vaultwarden = withCore ./modules/services/vaultwarden.nix;
      homeassistant = withCore ./modules/services/homeassistant.nix;
      authentik = withCore ./modules/services/authentik.nix;
      syncthing = withCore ./modules/services/syncthing.nix;
      scrutiny = withCore ./modules/services/scrutiny.nix;
      tailscale = withCore ./modules/services/tailscale.nix;
      wireguard = withCore (withVpn ./modules/services/wireguard.nix);
      cifs = withCore ./modules/services/cifs/cifs.nix;
      nas = withCore ./modules/services/nas/nas.nix;
      external = withCore ./modules/services/external.nix;
      nginx = {
        imports =
          secretModules
          ++ [
            ./modules/core/options.nix
            ./modules/services/external.nix
            ./modules/services/registry-integrations.nix
            ./modules/services/nginx/nginx.nix
          ];
      };
      homepage = {
        imports =
          secretModules
          ++ [
            ./modules/core/options.nix
            ./modules/services/external.nix
            ./modules/services/registry-integrations.nix
            ./modules/services/homepage/homepage.nix
          ];
      };

      program-core = ./modules/programs/core.nix;
      program-development = ./modules/programs/development.nix;
      program-hardware = ./modules/programs/hardware.nix;
      program-networking = ./modules/programs/networking.nix;
      program-media = ./modules/programs/media.nix;
      program-backup = ./modules/programs/backup.nix;
      program-zsh = ./modules/programs/zsh.nix;
      program-yazi = ./modules/programs/yazi.nix;

      profile-development = completePreset "development";
      profile-full = completePreset "full";
      profile-media-server = completePreset "media-server";
      profile-minimal = completePreset "minimal";
    };

    mkHost = configurationName: let
      hostDirectory = ./hosts + "/${configurationName}";
    in
      nixpkgs.lib.nixosSystem {
        modules = [
          publicModules.default
          hostDirectory
          {nixstead.host.configurationName = configurationName;}
        ];
      };

    hostEntries = lib.filterAttrs (
      name: entryType:
        entryType
        == "directory"
        && name != "definitions"
        && builtins.pathExists (./hosts + "/${name}/default.nix")
    ) (builtins.readDir ./hosts);

    discoveredHosts = lib.mapAttrs (configurationName: _: mkHost configurationName) hostEntries;

    mkApiCheck = system:
      import ./tests/public-api.nix {
        inherit nixpkgs lib publicModules system;
      };

    mkToolSet = system: let
      pkgs = import nixpkgs {inherit system;};
    in
      import ./scripts/package.nix {inherit pkgs;};
  in {
    nixosModules = publicModules;

    nixosConfigurations = discoveredHosts;

    templates.host = {
      path = ./templates/host;
      description = "Starter NixOS host using the Nixstead public module API";
    };

    lib.serviceRegistry = import ./modules/services/registry.nix;
    lib.testCatalogue = import ./tests/catalogue.nix {inherit lib;};

    formatter = lib.genAttrs supportedSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in
      pkgs.writeShellApplication {
        name = "nixstead-format";
        runtimeInputs = with pkgs; [treefmt alejandra ruff shfmt];
        text = ''exec treefmt --config-file ${./treefmt.toml} --tree-root "$PWD" "$@"'';
      });

    devShells = lib.genAttrs supportedSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      ci = pkgs.mkShellNoCC {
        packages = with pkgs; [ruff shellcheck actionlint];
      };
      default = pkgs.mkShell {
        packages = with pkgs; [alejandra ruff shfmt shellcheck treefmt git jq sops age rsync borgbackup sqlite (python3.withPackages (ps: [ps.textual ps.pyyaml ps.configobj]))];
      };
    });

    packages = lib.genAttrs supportedSystems (
      system: let
        pkgs = import nixpkgs {inherit system;};
        tools = mkToolSet system;
      in {
        option-docs =
          (pkgs.nixosOptionsDoc {
            options = {
              nixstead =
                (nixpkgs.lib.nixosSystem {
                  inherit system;
                  modules = [publicModules.default {system.stateVersion = "26.05";}];
                }).options.nixstead;
            };
            warningsAreErrors = false;
          }).optionsJSON;
        setup = import ./setup/package.nix {
          inherit pkgs;
          frameworkRoot = ./.;
        };
        setup-runtime = pkgs.buildEnv {
          name = "nixstead-setup-runtime";
          paths = [
            pkgs.age
            pkgs.jq
            (pkgs.python3.withPackages (ps: [ps.pyyaml ps.configobj]))
            pkgs.sops
            pkgs.ssh-to-age
          ];
        };
        container-image-runtime = pkgs.buildEnv {
          name = "nixstead-container-image-runtime";
          paths = [
            pkgs.coreutils
            pkgs.git
            pkgs.jq
            pkgs.skopeo
          ];
        };
        nixstead = tools.fullCli;
      }
    );

    apps = lib.genAttrs supportedSystems (system: let
      cli = (mkToolSet system).fullCli;
      setup = import ./setup/package.nix {
        pkgs = import nixpkgs {inherit system;};
        frameworkRoot = ./.;
      };
      app = {
        type = "app";
        program = "${cli}/bin/nixstead";
        inherit (cli) meta;
      };
    in {
      default = app;
      nixstead = app;
      setup = {
        type = "app";
        program = "${setup}/bin/nixstead-setup";
        inherit (setup) meta;
      };
    });

    checks = lib.genAttrs supportedSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: lib.getName pkg == "unrar";
      };
    in
      {
        public-module-api = mkApiCheck system;
        python =
          pkgs.runCommand "nixstead-python-tests" {
            nativeBuildInputs = [(pkgs.python3.withPackages (ps: [ps.textual ps.pyyaml ps.configobj])) pkgs.nix pkgs.sops pkgs.age pkgs.jq pkgs.sqlite pkgs.redis];
          } ''
            export XDG_CACHE_HOME="$TMPDIR/cache"
            export NIX_REMOTE="local?root=$TMPDIR/nix"
            cp -r ${./.} source
            chmod -R u+w source
            cd source
            python -m unittest discover -s tests -p 'test_*.py'
            touch $out
          '';
        service-docs = pkgs.runCommand "nixstead-service-docs-drift" {nativeBuildInputs = [pkgs.python3];} ''
          python ${./scripts/generate-service-docs.py} ${pkgs.writeText "registry.json" (builtins.toJSON (import ./modules/services/registry.nix))} ${./docs/generated/services.md} --check
          touch $out
        '';
        test-catalogue = pkgs.runCommand "nixstead-test-catalogue" {nativeBuildInputs = [pkgs.python3];} ''
          python ${./tests/suite_catalogue.py} \
            ${pkgs.writeText "test-catalogue.json" (builtins.toJSON self.lib.testCatalogue)} \
            ${./docs/generated/test-coverage.md} --check --system ${system} \
            --available-checks ${pkgs.writeText "check-names.json" (builtins.toJSON (builtins.attrNames self.checks.${system}))}
          touch $out
        '';
      }
      // (import ./tests/ci-evaluation.nix {inherit nixpkgs pkgs publicModules system;})
      // (import ./tests {inherit nixpkgs pkgs publicModules system;}));
  };
}
