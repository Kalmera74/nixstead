{
  config,
  lib,
  ...
}: let
  registryHelpers = import ./registry/lib.nix;
  serviceRegistry = import ./registry.nix;
  ociImageReferenceType = lib.types.strMatching registryHelpers.ociImageReferencePattern;
  cfg = config.nixstead.containerImages;
  serviceIds = builtins.attrNames cfg.overrides;
  knownService = serviceId:
    builtins.hasAttr serviceId serviceRegistry
    && serviceRegistry.${serviceId}.ociImages != {};
  knownComponent = serviceId: component:
    knownService serviceId
    && builtins.hasAttr component serviceRegistry.${serviceId}.ociImages;
  managedRegistry = lib.filterAttrs (_: entry: entry.ociImages != {}) serviceRegistry;
  overridesAreKnown =
    lib.all (
      serviceId:
        knownService serviceId
        && lib.all (knownComponent serviceId) (builtins.attrNames cfg.overrides.${serviceId})
    )
    serviceIds;
  overridesMatchRepositories =
    lib.all (
      serviceId:
        !knownService serviceId
        || lib.all (
          component:
            !knownComponent serviceId component
            || lib.hasPrefix
            "${serviceRegistry.${serviceId}.ociImages.${component}.repository}:"
            cfg.overrides.${serviceId}.${component}
        ) (builtins.attrNames cfg.overrides.${serviceId})
    )
    serviceIds;
  definitions = lib.concatLists (
    lib.mapAttrsToList (
      serviceId: entry:
        lib.mapAttrsToList (
          component: _:
            lib.mkIf
            (builtins.hasAttr serviceId cfg.overrides && builtins.hasAttr component cfg.overrides.${serviceId})
            (lib.setAttrByPath
              (["nixstead" "services"] ++ entry.optionPath ++ ["images" component])
              (lib.mkOverride 900 cfg.overrides.${serviceId}.${component}))
        )
        entry.ociImages
    )
    managedRegistry
  );
in {
  options.nixstead.containerImages.overrides = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf ociImageReferenceType);
    default = {};
    description = ''
      Host-specific, digest-pinned OCI image overrides keyed by registry service
      identifier and image component. Generated overrides have lower priority
      than image values declared directly in host configuration.
    '';
  };

  config = lib.mkMerge (
    [
      {
        assertions = [
          {
            assertion = overridesAreKnown;
            message = "Every nixstead.containerImages.overrides entry must name a registry-managed OCI service and component.";
          }
          {
            assertion = overridesMatchRepositories;
            message = "Every nixstead.containerImages.overrides value must use the component repository declared in the service registry.";
          }
        ];
      }
    ]
    ++ definitions
  );
}
