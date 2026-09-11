{
  mkSystem,
  lib,
  ...
}: let
  selected = {
    nixstead.services.arr = {
      swaparr.enable = true;
      sonarr = {
        enable = true;
        port = 28180;
      };
    };
  };
  config = (mkSystem [selected]).config;
  disabled = (mkSystem [selected {nixstead.services.arr.swaparr.enable = lib.mkForce false;}]).config;
  parent =
    (mkSystem [
      {
        nixstead.services.arr = {
          enable = true;
          swaparr.enable = false;
        };
      }
    ]).config;
  empty = (mkSystem [{nixstead.services.arr.swaparr.enable = true;}]).config;
  manual =
    (mkSystem [
      {
        nixstead.services.arr = {
          swaparr.enable = true;
          readarr.enable = true;
        };
      }
    ]).config;
  container = config.virtualisation.oci-containers.containers.swaparr-sonarr;
  workers = c: lib.filter (name: lib.hasPrefix "swaparr-" name) (builtins.attrNames c.virtualisation.oci-containers.containers);
in {
  validSystem = builtins.isString (mkSystem [selected]).config.system.build.toplevel.drvPath;
  selectedTargetsOnly = workers config == ["swaparr-sonarr"];
  noImplicitTargets = workers empty == [];
  disabledRemovesWorkers = workers disabled == [] && workers parent == [];
  customTargetEndpoint = container.environment.BASEURL == "http://127.0.0.1:28180" && container.environment.PLATFORM == "sonarr";
  pinnedApplication = container.image == config.nixstead.services.arr.swaparr.images.application && lib.hasInfix "@sha256:" container.image;
  runtimeCredentialFile = container.environmentFiles == ["/run/nixstead-credentials/sonarr/swaparr.env"] && !(container.environment ? APIKEY);
  manualReadarrRuntimeCredential = manual.virtualisation.oci-containers.containers.swaparr-readarr.environmentFiles == [manual.sops.templates."swaparr-readarr.env".path] && manual.sops.secrets ? "swaparr/readarrApiKey" && !(manual.virtualisation.oci-containers.containers.swaparr-readarr.environment ? APIKEY);
  transientWorker = container.volumes == [] && config.nixstead.serviceRegistry.swaparr.backup == null;
  boundedWorker = lib.elem "--memory=128m" container.extraOptions && lib.elem "--read-only" container.extraOptions;
  nativeHealthyValue = lib.elem "--health-cmd=grep -q 1 /tmp/swaparr.health" container.extraOptions;
  defaultDecisionThresholds = container.environment.MAX_STRIKES == "3" && container.environment.MAX_DOWNLOAD_TIME == "6h" && container.environment.STRIKE_QUEUED == "false";
  noInboundListener = config.nixstead.serviceRegistry.swaparr.proxy == null && config.nixstead.serviceRegistry.swaparr.homepage == null && config.nixstead.serviceRegistry.swaparr.listeners.settingsTcpPorts == [];
  invalidImageRejected = !(builtins.tryEval (mkSystem [{nixstead.services.arr.swaparr.images.application = "swaparr:latest";}]).config.nixstead.services.arr.swaparr.images.application).success;
}
