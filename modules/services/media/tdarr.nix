{
  config,
  lib,
  ...
}: let
  cfg = config.nixstead.services.media.tdarr;
in {
  imports = [
    ./tdarr-server.nix
    ./tdarr-node.nix
  ];

  config = lib.mkIf (cfg.server || cfg.node) {
    assertions = [
      {
        assertion = builtins.hasAttr config.services.tdarr.user config.users.users;
        message = "The configured Tdarr user must exist; custom services.tdarr.user accounts must be declared by the host.";
      }
    ];
    services.tdarr =
      {group = lib.mkDefault config.nixstead.host.groups.media;}
      // lib.optionalAttrs (cfg.paths.dataDir != null) {
        dataDir = cfg.paths.dataDir;
      };
  };
}
