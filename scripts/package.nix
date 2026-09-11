{
  pkgs,
  lib ? pkgs.lib,
  repositoryRoot ? null,
  configurationName ? null,
}: let
  scriptRoot = ./.;
  cliScript = ./nixstead.sh;
  generateCredentialsScript = ./generate-credential-files.sh;
  nixsteadLib = ./lib/nixstead.sh;
  secretSchema = ../secrets/secrets.example.yaml;
  setupProgram = import ../setup/package.nix {
    inherit pkgs;
    frameworkRoot = ../.;
  };

  baseInputs = with pkgs; [
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    util-linux
  ];
  nixInputs = baseInputs ++ [pkgs.jq pkgs.nix];
  secretInputs = nixInputs ++ [pkgs.sops];

  scriptSpecs = {
    backup-service-configs = {
      category = "admin";
      runtimeInputs = nixInputs ++ (with pkgs; [borgbackup docker-client postgresql python3 rsync systemd]);
    };
    check-homepage-secrets = {
      category = "admin";
      runtimeInputs = baseInputs ++ (with pkgs; [jq sops]);
    };
    check-secret-store-leaks = {
      category = "admin";
      runtimeInputs = secretInputs ++ [pkgs.ripgrep];
    };
    configure-homepage-integrations = {
      category = "admin";
      runtimeInputs = secretInputs;
    };
    configure-sops-host = {
      category = "admin";
      runtimeInputs = baseInputs ++ (with pkgs; [age ssh-to-age]);
    };
    container-images = {
      category = "admin";
      runtimeInputs = nixInputs ++ (with pkgs; [git skopeo]);
    };
    dev-healthcheck = {
      category = "admin";
      # rabbitmqctl lives in the full server package and is checked only when
      # RabbitMQ is enabled; do not add its roughly gigabyte-sized closure to
      # every administration-tools installation.
      runtimeInputs = secretInputs ++ (with pkgs; [curl iproute2 mongosh postgresql redis systemd]);
    };
    generate-credential-files = {
      category = "admin";
      runtimeInputs = secretInputs ++ [pkgs.python3];
    };
    health-homelab = {
      category = "admin";
      runtimeInputs = nixInputs ++ (with pkgs; [curl iproute2 iputils systemd]);
    };
    healthcheck = {
      category = "admin";
      runtimeInputs = secretInputs;
    };
    mirror-github-to-forgejo = {
      category = "admin";
      runtimeInputs = nixInputs ++ (with pkgs; [curl ripgrep]);
    };
    restore-service-configs = {
      category = "admin";
      runtimeInputs = nixInputs ++ (with pkgs; [borgbackup docker-client postgresql python3 rsync systemd]);
    };
    service-credentials = {
      category = "admin";
      runtimeInputs = secretInputs ++ [(pkgs.python3.withPackages (ps: [ps.pyyaml ps.configobj]))];
    };
    sync-pihole-local-dns = {
      category = "admin";
      file = ./sync-pihole-local-dns-from-nginx.sh;
      runtimeInputs = secretInputs ++ [pkgs.curl];
    };
    test-service-backup-restore = {
      category = "admin";
      runtimeInputs = nixInputs ++ [pkgs.borgbackup pkgs.postgresql pkgs.python3];
    };

    convert-videos-efficiently = {
      category = "media";
      runtimeInputs = baseInputs ++ [pkgs.ffmpeg_7];
    };
    copy-batocera-roms-to-romm = {
      category = "media";
      runtimeInputs = baseInputs ++ [pkgs.rsync];
    };
    hardlinks = {
      category = "media";
      runtimeInputs = baseInputs;
    };
    prepare-kavita-library = {
      category = "media";
      runtimeInputs = baseInputs ++ [pkgs.python3];
    };
  };

  mkCommand = name: spec: let
    scriptFile = spec.file or (scriptRoot + "/${name}.sh");
    configuredEnvironment =
      lib.optionalString (repositoryRoot != null) ''
        if [[ -z "''${NIXSTEAD_REPOSITORY_ROOT:-}" ]]; then
          export NIXSTEAD_REPOSITORY_ROOT=${lib.escapeShellArg repositoryRoot}
        fi
      ''
      + lib.optionalString (configurationName != null) ''
        if [[ -z "''${NIXSTEAD_HOST:-}" ]]; then
          export NIXSTEAD_HOST=${lib.escapeShellArg configurationName}
        fi
      '';
  in
    pkgs.writeShellApplication {
      name = "nixstead-${name}";
      inherit (spec) runtimeInputs;
      excludeShellChecks = [
        "SC1091"
        # Nix and jq expressions intentionally use shell-literal single quotes.
        "SC2016"
        # Several callers export context consumed by lib/nixstead.sh.
        "SC2034"
      ];
      text = ''
        if [[ -z "''${NIXSTEAD_SECRETS_DIR:-}" && -n "''${NIXCONFIG_SECRETS_DIR:-}" ]]; then
          export NIXSTEAD_SECRETS_DIR="$NIXCONFIG_SECRETS_DIR"
        fi
        ${lib.optionalString (name == "service-credentials") ''
          export NIXSTEAD_CREDENTIAL_STORE=${../modules/services/arr}/credential_store.py
        ''}
        export NIXSTEAD_GENERATE_CREDENTIALS_SCRIPT=${lib.escapeShellArg (toString generateCredentialsScript)}
        export NIXSTEAD_DATABASE_LIB=${./lib/service-databases.sh}
        export NIXSTEAD_ELASTICSEARCH_SNAPSHOT=${./lib/elasticsearch-snapshot.py}
        export NIXSTEAD_STATE_FILE_VALIDATOR=${./lib/validate-state-file.py}
        export NIXSTEAD_MONGODB_DIRECTORY_VALIDATOR=${./lib/validate-mongodb-directory.py}
        export NIXSTEAD_LIB=${lib.escapeShellArg (toString nixsteadLib)}
        export NIXSTEAD_SECRET_SCHEMA=${lib.escapeShellArg (toString secretSchema)}
        ${configuredEnvironment}
        if [[ -z "''${NIXSTEAD_REPOSITORY_ROOT:-}" && -f "$PWD/flake.nix" ]]; then
          export NIXSTEAD_REPOSITORY_ROOT="$PWD"
        fi

        ${builtins.readFile scriptFile}
      '';
      meta.description = "Nixstead command packaged from scripts/${builtins.baseNameOf scriptFile}";
    };

  commands = lib.mapAttrs mkCommand scriptSpecs;
  inputsFor = category:
    lib.concatLists (
      lib.mapAttrsToList (_: spec:
        if spec.category == category
        then spec.runtimeInputs
        else [])
      scriptSpecs
    );
  mkCli = includeMedia:
    pkgs.writeShellApplication {
      name = "nixstead";
      runtimeInputs =
        inputsFor "admin"
        ++ [setupProgram]
        ++ lib.optionals includeMedia (inputsFor "media");
      excludeShellChecks = [
        "SC1091"
        "SC2016"
        "SC2034"
      ];
      text = ''
        if [[ -z "''${NIXSTEAD_SECRETS_DIR:-}" && -n "''${NIXCONFIG_SECRETS_DIR:-}" ]]; then
          export NIXSTEAD_SECRETS_DIR="$NIXCONFIG_SECRETS_DIR"
        fi
        export NIXSTEAD_SCRIPT_ROOT=${lib.escapeShellArg (toString scriptRoot)}
        export NIXSTEAD_MEDIA_ENABLED=${lib.boolToString includeMedia}
        export NIXSTEAD_CREDENTIAL_STORE=${../modules/services/arr}/credential_store.py
        export NIXSTEAD_GENERATE_CREDENTIALS_SCRIPT=${lib.escapeShellArg (toString generateCredentialsScript)}
        export NIXSTEAD_DATABASE_LIB=${./lib/service-databases.sh}
        export NIXSTEAD_ELASTICSEARCH_SNAPSHOT=${./lib/elasticsearch-snapshot.py}
        export NIXSTEAD_STATE_FILE_VALIDATOR=${./lib/validate-state-file.py}
        export NIXSTEAD_MONGODB_DIRECTORY_VALIDATOR=${./lib/validate-mongodb-directory.py}
        export NIXSTEAD_LIB=${lib.escapeShellArg (toString nixsteadLib)}
        export NIXSTEAD_SECRET_SCHEMA=${lib.escapeShellArg (toString secretSchema)}
        export NIXSTEAD_SETUP_PROGRAM=${lib.escapeShellArg "${setupProgram}/bin/nixstead-setup"}
        ${lib.optionalString (repositoryRoot != null) ''
          if [[ -z "''${NIXSTEAD_REPOSITORY_ROOT:-}" ]]; then
            export NIXSTEAD_REPOSITORY_ROOT=${lib.escapeShellArg repositoryRoot}
          fi
        ''}
        ${lib.optionalString (configurationName != null) ''
          if [[ -z "''${NIXSTEAD_HOST:-}" ]]; then
            export NIXSTEAD_HOST=${lib.escapeShellArg configurationName}
          fi
        ''}
        if [[ -z "''${NIXSTEAD_REPOSITORY_ROOT:-}" && -f "$PWD/flake.nix" ]]; then
          export NIXSTEAD_REPOSITORY_ROOT="$PWD"
        fi

        ${builtins.readFile cliScript}
      '';
      meta.description = "Operate and maintain a Nixstead host";
    };
  adminCli = mkCli false;
  fullCli = mkCli true;
in {
  inherit commands adminCli fullCli;
}
