{
  config,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.localai.llamacpp;
  configuredOllamaModelsDir = config.nixstead.services.localai.ollama.paths.modelsDir;
  acceleration = config.nixstead.host.hardware.gpu.acceleration;
  ollamaBacked = cfg.ollamaModel != null;
  llamaCppPackage = pkgs.llama-cpp.override {
    cudaSupport = acceleration == "cuda";
    rocmSupport = acceleration == "rocm";
  };
  llamaCppSettings =
    (
      if ollamaBacked
      then builtins.removeAttrs cfg.settings ["model" "mmproj"]
      else cfg.settings
    )
    // {
      host = serviceBindAddress "llamacpp";
      port = cfg.port;
    };
  llamaCppCommandLine = toString (lib.cli.toCommandLine (optionName: {
      option =
        if builtins.stringLength optionName > 1
        then "--${optionName}"
        else "-${optionName}";
      sep = " ";
      explicitBool = false;
      formatArg = lib.generators.mkValueStringDefault {};
    })
    config.services.llama-cpp.settings);
  ollamaExecutable = lib.getExe config.services.ollama.package;
  llamaServerExecutable = lib.getExe' config.services.llama-cpp.package "llama-server";
  ollamaModelsMount = "/run/llama-cpp/ollama-models";
  ollamaModelLauncher = pkgs.writeShellScript "llama-cpp-from-ollama" ''
    set -euo pipefail

    ollama_models_dir=${lib.escapeShellArg config.services.ollama.modelsDir}
    ollama_models_mount=${lib.escapeShellArg ollamaModelsMount}
    modelfile=""
    for attempt in {1..30}; do
      if modelfile="$(
        OLLAMA_HOST=${lib.escapeShellArg "${config.services.ollama.host}:${toString config.services.ollama.port}"} \
          ${ollamaExecutable} show ${lib.escapeShellArg cfg.ollamaModel} --modelfile
      )"; then
        break
      fi
      if (( attempt == 30 )); then
        echo "Ollama model is not available: ${cfg.ollamaModel}" >&2
        exit 1
      fi
      ${lib.getExe' pkgs.coreutils "sleep"} 1
    done

    mapfile -t model_paths < <(
      printf '%s\n' "$modelfile" \
        | ${lib.getExe pkgs.gawk} '$1 == "FROM" && $2 ~ "^/" { print $2 }'
    )

    if (( ''${#model_paths[@]} < 1 || ''${#model_paths[@]} > 2 )); then
      echo "Expected one model blob and at most one projector for ${cfg.ollamaModel}, found ''${#model_paths[@]}" >&2
      exit 1
    fi

    mounted_model_paths=()
    for model_path in "''${model_paths[@]}"; do
      case "$model_path" in
        "$ollama_models_dir"/blobs/sha256-*) ;;
        *) echo "Refusing unexpected Ollama model path: $model_path" >&2; exit 1 ;;
      esac

      mounted_model_path="$ollama_models_mount/blobs/''${model_path##*/}"
      if [[ ! -r "$mounted_model_path" ]]; then
        echo "Ollama model blob is not readable through the llama.cpp mount: $mounted_model_path" >&2
        exit 1
      fi
      mounted_model_paths+=("$mounted_model_path")
    done

    model_args=(
      --model "''${mounted_model_paths[0]}"
      --alias ${lib.escapeShellArg cfg.ollamaModel}
    )
    if (( ''${#mounted_model_paths[@]} == 2 )); then
      model_args+=(--mmproj "''${mounted_model_paths[1]}")
    fi

    exec ${llamaServerExecutable} ${llamaCppCommandLine} "''${model_args[@]}"
  '';
in {
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !ollamaBacked || config.nixstead.services.localai.ollama.enable;
          message = "llama.cpp requires the local Ollama service when llamacpp.ollamaModel is set.";
        }
      ];

      services.llama-cpp = {
        enable = true;
        package = lib.mkDefault llamaCppPackage;
        settings = llamaCppSettings;
      };
    })
    (lib.mkIf (cfg.enable && ollamaBacked) {
      services.ollama.user = lib.mkDefault "ollama";

      systemd.services.llama-cpp = {
        requires = ["ollama.service"];
        after = ["ollama.service"];
        unitConfig.RequiresMountsFor = lib.optional (configuredOllamaModelsDir != null) config.services.ollama.modelsDir;
        environment = {
          HOME = config.services.ollama.home;
          OLLAMA_MODELS = config.services.ollama.modelsDir;
        };
        serviceConfig = {
          User = config.services.ollama.user;
          Group = config.services.ollama.group;
          RuntimeDirectory = "llama-cpp";
          BindReadOnlyPaths = ["${config.services.ollama.modelsDir}:${ollamaModelsMount}"];
          SupplementaryGroups = lib.optional (configuredOllamaModelsDir != null) config.nixstead.host.groups.media;
          ExecStart = lib.mkForce ollamaModelLauncher;
        };
      };
    })
  ];
}
