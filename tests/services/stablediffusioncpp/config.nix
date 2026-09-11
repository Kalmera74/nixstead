{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  configured =
    (mkSystem [
      {
        nixstead.services.localai.stablediffusioncpp = {
          enable = true;
          port = 21234;
          paths = {
            modelFile = null;
            modelFiles = {
              "diffusion-model" = "/srv/models/diffusion.gguf";
              vae = "/srv/models/vae.gguf";
            };
            loraDir = "/srv/models/loras";
            embeddingsDir = "/srv/models/embeddings";
            upscalersDir = "/srv/models/upscalers";
          };
          settings = {
            threads = 2;
            "listen-ip" = "0.0.0.0";
            "listen-port" = 1;
          };
        };
      }
    ]).config;
  command = configured.systemd.services.stable-diffusion-cpp.serviceConfig.ExecStart;
  rejects = paths: fragment: let
    c =
      (mkSystem [
        {
          nixstead.services.localai.stablediffusioncpp = {
            enable = true;
            inherit paths;
          };
        }
      ]).config;
  in
    lib.any (a: !a.assertion && lib.hasInfix fragment a.message) c.assertions;
in
  (serviceContract {
    id = "stablediffusioncpp";
    group = "localai";
    port = 21234;
    nativeEnabled = c: c.systemd.services ? stable-diffusion-cpp;
  })
  // {
    splitModelMounts = lib.all (p: lib.elem p configured.systemd.services.stable-diffusion-cpp.unitConfig.RequiresMountsFor) ["/srv/models/diffusion.gguf" "/srv/models/vae.gguf" "/srv/models/loras" "/srv/models/embeddings" "/srv/models/upscalers"];
    splitModelsMustExist = configured.systemd.services.stable-diffusion-cpp.unitConfig.ConditionPathExists == ["/srv/models/diffusion.gguf" "/srv/models/vae.gguf"];
    nativeCommandSettings = lib.all (s: lib.hasInfix s command) ["--listen-ip 127.0.0.1" "--listen-port 21234" "--threads 2" "--diffusion-model /srv/models/diffusion.gguf" "--vae /srv/models/vae.gguf"];
    missingModelRejected = rejects {modelFile = null;} "requires stablediffusioncpp.paths.modelFile";
    duplicateModelRejected = rejects {modelFiles.model = "/srv/other.gguf";} "configured by both";
    reservedModelOptionRejected = rejects {modelFiles."listen-port" = "/srv/invalid";} "cannot manage module-owned options";
    cpuNeedsNoGpuGroups = !(lib.elem "render" configured.users.users.stable-diffusion-cpp.extraGroups);
  }
