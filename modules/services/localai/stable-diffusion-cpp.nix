{
  config,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.localai.stablediffusioncpp;
  acceleration = config.nixstead.host.hardware.gpu.acceleration;
  package =
    if acceleration == "cuda"
    then pkgs.stable-diffusion-cpp-cuda
    else if acceleration == "rocm"
    then pkgs.stable-diffusion-cpp-rocm
    else pkgs.stable-diffusion-cpp;
  pnpm = pkgs.pnpm_10;
  frontend = pkgs.stdenvNoCC.mkDerivation {
    pname = "stable-diffusion-cpp-frontend";
    inherit (pkgs.stable-diffusion-cpp) version src;

    pnpmRoot = "examples/server/frontend";
    pnpmDeps = pkgs.fetchPnpmDeps {
      pname = "stable-diffusion-cpp-frontend";
      inherit (pkgs.stable-diffusion-cpp) version src;
      inherit pnpm;
      sourceRoot = "${pkgs.stable-diffusion-cpp.src.name}/examples/server/frontend";
      fetcherVersion = 3;
      hash = "sha256-ocImnMPFHhnuJj3gUN8WsfSur/peLIKiozpPDHU1tAA=";
    };

    nativeBuildInputs = [
      pkgs.nodejs
      pkgs.pnpmConfigHook
      pnpm
    ];

    buildPhase = ''
      runHook preBuild
      pnpm -C "$pnpmRoot" build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm644 "$pnpmRoot/dist/index.html" "$out/index.html"
      runHook postInstall
    '';
  };
  reservedModelFileNames = [
    "listen-ip"
    "listen-port"
    "serve-html-path"
    "lora-model-dir"
    "embd-dir"
    "hires-upscalers-dir"
  ];
  configuredModelFiles =
    cfg.paths.modelFiles
    // lib.optionalAttrs (cfg.paths.modelFile != null) {
      model = cfg.paths.modelFile;
    };
  conflictingModelFileNames = lib.intersectLists reservedModelFileNames (builtins.attrNames cfg.paths.modelFiles);
  managedSettingNames =
    reservedModelFileNames
    ++ builtins.attrNames configuredModelFiles;
  serverSettings =
    builtins.removeAttrs cfg.settings managedSettingNames
    // configuredModelFiles
    // {
      "listen-ip" = serviceBindAddress "stablediffusioncpp";
      "listen-port" = cfg.port;
      "serve-html-path" = "${frontend}/index.html";
      "lora-model-dir" = cfg.paths.loraDir;
      "embd-dir" = cfg.paths.embeddingsDir;
      "hires-upscalers-dir" = cfg.paths.upscalersDir;
    };
  commandLine = toString (lib.cli.toCommandLine (optionName: {
      option =
        if builtins.stringLength optionName > 1
        then "--${optionName}"
        else "-${optionName}";
      sep = " ";
      explicitBool = false;
      formatArg = lib.generators.mkValueStringDefault {};
    })
    serverSettings);
  modelConfigured =
    builtins.hasAttr "model" configuredModelFiles
    || builtins.hasAttr "diffusion-model" configuredModelFiles
    || builtins.hasAttr "model" cfg.settings
    || builtins.hasAttr "diffusion-model" cfg.settings;
  modelPaths = lib.unique (builtins.attrValues configuredModelFiles);
  runtimePaths =
    [
      cfg.paths.loraDir
      cfg.paths.embeddingsDir
      cfg.paths.upscalersDir
    ]
    ++ modelPaths;
  conditionPathValue =
    if builtins.length modelPaths == 1
    then builtins.head modelPaths
    else modelPaths;
in {
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = modelConfigured;
        message = "stable-diffusion.cpp requires stablediffusioncpp.paths.modelFile, a model/diffusion-model entry in paths.modelFiles, or a model/diffusion-model entry in settings.";
      }
      {
        assertion = cfg.paths.modelFile == null || !(builtins.hasAttr "model" cfg.paths.modelFiles);
        message = "stable-diffusion.cpp model is configured by both paths.modelFile and paths.modelFiles.model; set paths.modelFile to null when using the modelFiles entry.";
      }
      {
        assertion = conflictingModelFileNames == [];
        message = "stable-diffusion.cpp paths.modelFiles cannot manage module-owned options: ${lib.concatStringsSep ", " conflictingModelFileNames}.";
      }
    ];

    users.groups.stable-diffusion-cpp = {};
    users.users.stable-diffusion-cpp = {
      isSystemUser = true;
      group = "stable-diffusion-cpp";
      extraGroups =
        [config.nixstead.host.groups.media]
        ++ lib.optionals (acceleration != "none") [
          "render"
          "video"
        ];
      home = "/var/lib/stable-diffusion-cpp";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/stable-diffusion-cpp 0750 stable-diffusion-cpp stable-diffusion-cpp -"
      "d /var/lib/stable-diffusion-cpp/models 0750 stable-diffusion-cpp stable-diffusion-cpp -"
      "d /var/lib/stable-diffusion-cpp/loras 0750 stable-diffusion-cpp stable-diffusion-cpp -"
      "d /var/lib/stable-diffusion-cpp/embeddings 0750 stable-diffusion-cpp stable-diffusion-cpp -"
      "d /var/lib/stable-diffusion-cpp/upscalers 0750 stable-diffusion-cpp stable-diffusion-cpp -"
    ];

    systemd.services.stable-diffusion-cpp = {
      description = "stable-diffusion.cpp server and web frontend";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      unitConfig =
        {
          RequiresMountsFor = runtimePaths;
        }
        // lib.optionalAttrs (modelPaths != []) {
          ConditionPathExists = conditionPathValue;
        };
      serviceConfig = {
        Type = "simple";
        User = "stable-diffusion-cpp";
        Group = "stable-diffusion-cpp";
        WorkingDirectory = "/var/lib/stable-diffusion-cpp";
        ExecStart = "${lib.getExe' package "sd-server"} ${commandLine}";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };
  };
}
