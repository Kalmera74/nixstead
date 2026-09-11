{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixstead.host.user;
  generatedDirectoryParts = lib.splitString "/" cfg.generatedFilesDirectory;
  generatedDirectories =
    lib.genList (index: "${config.users.users.${cfg.name}.home}/${lib.concatStringsSep "/" (lib.take (index + 1) generatedDirectoryParts)}")
    (lib.length generatedDirectoryParts);
  generatedFilesPath = "${config.users.users.${cfg.name}.home}/${cfg.generatedFilesDirectory}";
  sopsAgeKeyFile = "${generatedFilesPath}/sops-age-key.txt";
  deprecatedProjectAgeKeyFile = "${config.users.users.${cfg.name}.home}/.local/share/nixconfig/sops-age-key.txt";
  legacySopsAgeKeyFile = "${config.users.users.${cfg.name}.home}/.config/sops/age/keys.txt";
in {
  users.groups.${config.nixstead.host.groups.media}.gid = config.nixstead.host.groups.mediaGid;

  # The managed user always uses Zsh as its login shell, so the corresponding
  # NixOS program module must be enabled as part of the same abstraction.
  programs.zsh.enable = lib.mkIf cfg.enable true;

  environment.sessionVariables.SOPS_AGE_KEY_FILE = lib.mkIf cfg.enable sopsAgeKeyFile;
  systemd.tmpfiles.rules = lib.mkIf cfg.enable (map (path: "d ${path} 0700 ${cfg.name} ${config.users.users.${cfg.name}.group} -") generatedDirectories);

  system.activationScripts.nixstead-user-generated-files = lib.mkIf cfg.enable {
    deps = ["users"];
    text = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 \
        -o ${lib.escapeShellArg cfg.name} \
        -g ${lib.escapeShellArg config.users.users.${cfg.name}.group} \
        ${lib.escapeShellArgs generatedDirectories}
      if [ ! -e ${lib.escapeShellArg sopsAgeKeyFile} ]; then
        if [ -f ${lib.escapeShellArg deprecatedProjectAgeKeyFile} ]; then
          ${pkgs.coreutils}/bin/mv -- \
            ${lib.escapeShellArg deprecatedProjectAgeKeyFile} \
            ${lib.escapeShellArg sopsAgeKeyFile}
        elif [ -f ${lib.escapeShellArg legacySopsAgeKeyFile} ]; then
          ${pkgs.coreutils}/bin/mv -- \
            ${lib.escapeShellArg legacySopsAgeKeyFile} \
            ${lib.escapeShellArg sopsAgeKeyFile}
        fi
      fi
      if [ -f ${lib.escapeShellArg sopsAgeKeyFile} ]; then
        ${pkgs.coreutils}/bin/chown \
          ${lib.escapeShellArg "${cfg.name}:${config.users.users.${cfg.name}.group}"} \
          ${lib.escapeShellArg sopsAgeKeyFile}
        ${pkgs.coreutils}/bin/chmod 0600 ${lib.escapeShellArg sopsAgeKeyFile}
      fi
    '';
  };

  users.users = lib.mkIf cfg.enable {
    ${cfg.name} = {
      isNormalUser = true;
      inherit (cfg) description uid;
      shell = pkgs.zsh;
      extraGroups = lib.unique ([config.nixstead.host.groups.media] ++ cfg.extraGroups);
      openssh.authorizedKeys.keys = config.nixstead.host.ssh.authorizedKeys;
    };
  };
}
