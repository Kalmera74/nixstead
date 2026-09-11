{pkgs, ...}: {
  environment.systemPackages = [pkgs.yazi];

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
