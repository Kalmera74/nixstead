{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  configured =
    (mkSystem [
      {
        nixstead.services.localai.ollama = {
          enable = true;
          port = 21434;
          paths.modelsDir = "/srv/models/ollama";
        };
      }
    ]).config;
  invalid = (mkSystem [{nixstead.services.localai.ollama.paths.modelsDir = "relative/models";}]).config;
in
  (serviceContract {
    id = "ollama";
    group = "localai";
    port = 21434;
    nativeEnabled = c: c.services.ollama.enable;
  })
  // {
    nativeModelPath = configured.services.ollama.modelsDir == "/srv/models/ollama";
    waitsForModelMount = lib.elem "/srv/models/ollama" configured.systemd.services.ollama.unitConfig.RequiresMountsFor;
    loopbackListener = configured.services.ollama.host == "127.0.0.1" && configured.services.ollama.port == 21434;
    cpuDefault = configured.nixstead.host.hardware.gpu.acceleration == "none" && configured.services.ollama.package.pname == "ollama";
    modelAccess = configured.services.ollama.user == "ollama" && lib.elem configured.nixstead.host.groups.media configured.systemd.services.ollama.serviceConfig.SupplementaryGroups;
    sharedModelGroupExists = configured.users.groups.${configured.nixstead.host.groups.media}.gid == configured.nixstead.host.groups.mediaGid;
    relativeModelsRejected = !(builtins.tryEval invalid.nixstead.services.localai.ollama.paths.modelsDir).success;
  }
