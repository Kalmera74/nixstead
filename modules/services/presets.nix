{
  config,
  lib,
  ...
}: let
  cfg = config.nixstead.preset;
  serviceRegistry = import ./registry.nix;
  presetNames = [
    "none"
    "minimal"
    "media-starter"
    "media-server"
    "development"
    "full"
  ];

  presetEntries =
    lib.filterAttrs (
      _: entry:
        entry.setup
        != null
        && entry.setup.presetControlled
    )
    serviceRegistry;

  optionPathFor = entry:
    ["nixstead" "services"]
    ++ (entry.setup.optionPath or entry.enablePath);

  serviceDefaults = map (
    entry:
      lib.setAttrByPath
      (optionPathFor entry)
      (lib.mkIf (lib.elem cfg entry.setup.presets) (lib.mkDefault true))
  ) (lib.attrValues presetEntries);

  # Preserve the public stack-level state exposed by the former profiles. Dev
  # presets intentionally select children because Gitea is an opt-in Forgejo
  # alternative, so nixstead.services.dev.enable must remain false.
  presetParentStacks = {
    minimal = [];
    media-starter = [];
    media-server = [
      ["arr" "enable"]
      ["media" "enable"]
    ];
    development = [];
    full = [
      ["arr" "enable"]
      ["media" "enable"]
      ["localai" "enable"]
      ["productivity" "enable"]
    ];
    none = [];
  };

  parentDefaults = lib.concatLists (lib.mapAttrsToList (
      preset: paths:
        map (
          path:
            lib.setAttrByPath
            (["nixstead" "services"] ++ path)
            (lib.mkIf (cfg == preset) (lib.mkDefault true))
        )
        paths
    )
    presetParentStacks);
in {
  options.nixstead.preset = lib.mkOption {
    type = lib.types.enum presetNames;
    default = "none";
    description = "Registry-driven service preset used as overrideable host defaults.";
  };

  config = lib.mkMerge (serviceDefaults ++ parentDefaults);
}
