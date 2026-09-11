{config, ...}: let
  repoPath = config.nixstead.host.repositoryPath;
  configurationName = config.nixstead.host.configurationName;
in {
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    ohMyZsh = {
      enable = true;
      theme = "agnoster";
    };

    shellAliases = {
      l = "ls -lh";
      ll = "ls -lha";
      ".." = "cd ..";

      yy = "yazi";
      si = "swayimg";

      ga = "git add";
      gs = "git status";
      gm = "git commit";
      lg = "lazygit";
      ldoc = "lazydocker";

      v = "nvim";
      sv = "sudo nvim";
      sev = "sudoedit";

      rebuild = "sudo nixos-rebuild switch --flake ${repoPath}#${configurationName}";
      rebuild-clean = "sudo nixos-rebuild switch --flake ${repoPath}#${configurationName}";
      rebuild-external = "sudo env NIXSTEAD_SECRETS_DIR=${repoPath}/secrets nixos-rebuild switch --impure --flake ${repoPath}#${configurationName}";
      update = "nix flake update ${repoPath}";
      dry-rebuild = "sudo nixos-rebuild dry-activate --flake ${repoPath}#${configurationName}";
      ns = "nix-shell";
      ngc = "sudo nix-collect-garbage -d";

      mv = "mv -i";
    };
  };
}
