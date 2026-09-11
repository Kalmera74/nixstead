{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf mkOption types;

  cfg = config.nixstead.secrets;
  configuredSecretsDirectory = builtins.getEnv "NIXSTEAD_SECRETS_DIR";
  legacySecretsDirectory = builtins.getEnv "NIXCONFIG_SECRETS_DIR";
  secretsDirectory =
    if configuredSecretsDirectory != ""
    then configuredSecretsDirectory
    else legacySecretsDirectory;
  repositorySopsFile = ../../secrets + "/${config.nixstead.host.configurationName}.yaml";
  externalSopsFile =
    if secretsDirectory == ""
    then repositorySopsFile
    else "${secretsDirectory}/${config.nixstead.host.configurationName}.yaml";

  enabledSecretDomains = lib.unique (lib.concatMap (entry: entry.secrets) (
    lib.attrValues (lib.filterAttrs (_: entry: entry.enabled) config.nixstead.serviceRegistry)
  ));

  secretPath = name: config.sops.secrets.${name}.path;
  secretPlaceholder = name: config.sops.placeholder.${name};
in {
  options.nixstead.secrets = {
    enable = lib.mkEnableOption "runtime secret decryption with sops-nix";

    sopsFile = mkOption {
      type = types.path;
      default = externalSopsFile;
      defaultText = lib.literalExpression ''
        let
          configuredDir = builtins.getEnv "NIXSTEAD_SECRETS_DIR";
          legacyDir = builtins.getEnv "NIXCONFIG_SECRETS_DIR";
          dir = if configuredDir != "" then configuredDir else legacyDir;
        in if dir == ""
           then <repository>/secrets/''${config.nixstead.host.configurationName}.yaml
           else "''${dir}/''${config.nixstead.host.configurationName}.yaml"
      '';
      description = ''
        Encrypted SOPS YAML file for this host. When NIXSTEAD_SECRETS_DIR is
        set, the default is <directory>/<configurationName>.yaml; otherwise it
        is the repository's secrets/<configurationName>.yaml. The deprecated
        NIXCONFIG_SECRETS_DIR name remains supported for existing deployments.
      '';
    };

    age = {
      sshKeyPaths = mkOption {
        type = types.listOf types.path;
        default = ["/etc/ssh/ssh_host_ed25519_key"];
        description = "SSH host private keys from which sops-nix derives age identities.";
      };

      keyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/var/lib/sops-nix/key.txt";
        description = "Optional dedicated age identity file instead of, or in addition to, SSH host keys.";
      };
    };
  };

  config = {
    _module.args = {
      inherit secretPath secretPlaceholder;
    };

    assertions = [
      {
        assertion = enabledSecretDomains == [] || cfg.enable || config.sops.secrets == {};
        message = "Enabled services require secret domains (${lib.concatStringsSep ", " enabledSecretDomains}); set nixstead.secrets.enable = true.";
      }
    ];

    sops = mkIf cfg.enable {
      defaultSopsFile = cfg.sopsFile;
      defaultSopsFormat = "yaml";
      # External NIXSTEAD_SECRETS_DIR (or legacy NIXCONFIG_SECRETS_DIR) files
      # intentionally remain outside the flake source/store and are read by
      # sops-nix during activation.
      validateSopsFiles = secretsDirectory == "";
      age = {
        inherit (cfg.age) sshKeyPaths keyFile;
      };
    };
  };
}
