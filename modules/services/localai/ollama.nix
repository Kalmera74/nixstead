{
  config,
  host,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.localai;
  modelsDir = cfg.ollama.paths.modelsDir;
  acceleration = config.nixstead.host.hardware.gpu.acceleration;
  ollamaPackage =
    if acceleration == "cuda"
    then pkgs.ollama-cuda
    else if acceleration == "rocm"
    then pkgs.ollama-rocm
    else pkgs.ollama;
in {
  config = lib.mkIf cfg.ollama.enable (lib.mkMerge [
    {
      services.ollama = {
        enable = true;
        package = lib.mkDefault ollamaPackage;
        host = serviceBindAddress "ollama";
        port = config.nixstead.services.localai.ollama.port;
      };
    }
    (lib.mkIf (modelsDir != null) {
      services.ollama = {
        inherit modelsDir;
        user = lib.mkDefault "ollama";
      };

      systemd.services.ollama = {
        unitConfig.RequiresMountsFor = [modelsDir];
        serviceConfig.SupplementaryGroups = [config.nixstead.host.groups.media];
      };
    })
  ]);
}
