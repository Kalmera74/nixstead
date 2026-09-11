{
  pkgs,
  lib ? pkgs.lib,
  frameworkRoot ? ../.,
}: let
  python = pkgs.python3.withPackages (ps: [ps.configobj ps.pyyaml]);
  runtimeInputs = with pkgs; [
    age
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    jq
    nix
    openssh
    python
    sops
    ssh-to-age
    util-linux
  ];
in
  pkgs.python3Packages.buildPythonApplication {
    pname = "nixstead-setup";
    version = "0.1.0";
    pyproject = true;
    src = ./.;
    dependencies = [pkgs.python3Packages.textual];
    nativeBuildInputs = [pkgs.python3Packages.setuptools pkgs.makeWrapper];
    postInstall = ''
      wrapProgram $out/bin/nixstead-setup \
        --prefix PATH : ${lib.makeBinPath runtimeInputs} \
        --set NIXSTEAD_FRAMEWORK_ROOT ${lib.escapeShellArg (toString frameworkRoot)} \
        --set NIXSTEAD_HEALTHCHECK_SCRIPT ${lib.escapeShellArg (toString ../scripts/healthcheck.sh)} \
        --set NIXSTEAD_SOPS_HELPER ${lib.escapeShellArg (toString ../scripts/configure-sops-host.sh)} \
        --set NIXSTEAD_CREDENTIAL_HELPER ${lib.escapeShellArg (toString ../scripts/generate-credential-files.sh)} \
        --set NIXSTEAD_GENERATE_CREDENTIALS_SCRIPT ${lib.escapeShellArg (toString ../scripts/generate-credential-files.sh)} \
        --set NIXSTEAD_CREDENTIAL_STORE ${lib.escapeShellArg (toString ../modules/services/arr/credential_store.py)} \
        --set NIXSTEAD_LIB ${lib.escapeShellArg (toString ../scripts/lib/nixstead.sh)} \
        --set NIXSTEAD_SECRET_SCHEMA ${lib.escapeShellArg (toString ../secrets/secrets.example.yaml)}
    '';
    meta.description = "Generate and validate Nixstead host configurations";
  }
