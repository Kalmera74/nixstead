{lib, ...}: {
  # Replace or extend this with the generated hardware configuration before
  # installing on physical hardware.
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # New 26.05 installations may use this value. Existing systems must retain
  # the stateVersion from their original installation.
  system.stateVersion = "26.05";

  nixstead.preset = "minimal";
  nixstead.tools.enable = true;

  # Managed with `nixstead images` from the packaged tool set. The
  # separate file keeps local upgrades and downgrades easy to review.
  nixstead.containerImages.overrides =
    if builtins.pathExists ./container-images.nix
    then import ./container-images.nix
    else {};

  # Enable after encrypting a host file as documented in docs/secrets.md.
  # nixstead.secrets = {
  #   enable = true;
  #   sopsFile = ./secrets/my-host.yaml;
  # };

  nixstead.host = {
    hostName = "my-host";
    configurationName = "my-host";
    repositoryPath = "/etc/nixos";
    network.lan = "192.168.1.10";
    user = {
      enable = true;
      name = "admin";
      description = "Administrator";
      extraGroups = ["networkmanager" "wheel"];
    };
  };
}
