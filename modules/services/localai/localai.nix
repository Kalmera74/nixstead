{
  config,
  lib,
  optionalRuntimePathOption,
  runtimePathOption,
  serviceOptionFromRegistry,
  ...
}: let
  cfg = config.nixstead.services.localai;
in {
  # Local AI modules can be imported without the complete host/user modules.
  # Their optional shared-model access must reference an existing group.
  config.users.groups.${config.nixstead.host.groups.media}.gid = config.nixstead.host.groups.mediaGid;

  options.nixstead.services.localai = {
    enable = lib.mkEnableOption "Local AI stack";
    ollama = serviceOptionFromRegistry "ollama" {
      enable = cfg.enable;
      pathOptions.modelsDir = optionalRuntimePathOption "Optional absolute directory containing Ollama model manifests and blobs; the native NixOS default is used when unset.";
    };
    llamacpp = serviceOptionFromRegistry "llamacpp" {
      enable = cfg.enable;
      extraOptions = {
        ollamaModel = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "qwen3.8:latest";
          description = "Optional installed Ollama model to resolve and load directly from Ollama's blob store.";
        };
        settings = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {};
          example = {
            "hf-repo" = "Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M";
            "ctx-size" = 4096;
          };
          description = "Additional command-line settings passed to llama-server; host and port are registry-managed.";
        };
      };
    };
    stablediffusioncpp = serviceOptionFromRegistry "stablediffusioncpp" {
      enable = cfg.enable;
      pathOptions = {
        modelFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = "/var/lib/stable-diffusion-cpp/models/model.safetensors";
          example = "/srv/models/stable-diffusion/sd-v1-5.safetensors";
          description = "Optional absolute path to a complete Stable Diffusion checkpoint passed as --model; set to null when modelFiles supplies split model components.";
        };
        modelFiles = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = {};
          example = {
            "diffusion-model" = "/srv/models/wan/wan2.1-t2v-1.3b.safetensors";
            vae = "/srv/models/wan/wan_2.1_vae.safetensors";
            t5xxl = "/srv/models/wan/umt5-xxl-encoder-Q8_0.gguf";
          };
          description = "Absolute model-component files keyed by their sd-server command-line option name, without leading dashes. The service waits for and passes every entry to sd-server, supporting split image and video pipelines as well as motion modules.";
        };
        loraDir = runtimePathOption "/var/lib/stable-diffusion-cpp/loras" "Absolute directory containing LoRA models exposed to the web frontend.";
        embeddingsDir = runtimePathOption "/var/lib/stable-diffusion-cpp/embeddings" "Absolute directory containing textual-inversion embeddings.";
        upscalersDir = runtimePathOption "/var/lib/stable-diffusion-cpp/upscalers" "Absolute directory containing high-resolution upscaler models.";
      };
      extraOptions.settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
        example = {
          threads = 8;
          "vae-tiling" = true;
          "diffusion-fa" = true;
        };
        description = "Additional command-line settings passed to sd-server; listener, frontend, and typed path settings are registry-managed.";
      };
    };
    openwebui = serviceOptionFromRegistry "openwebui" {
      enable = cfg.enable;
      extraOptions = {
        ollamaUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "http://ollama.internal:11434";
          description = "Optional external Ollama endpoint used when the local Ollama service is disabled.";
        };
        environmentFile = optionalRuntimePathOption "Optional absolute environment file containing Open WebUI secrets such as WEBUI_ADMIN_EMAIL and WEBUI_ADMIN_PASSWORD, typically a sops-nix template path.";
      };
    };
  };

  imports = [
    ./ollama.nix
    ./llama-cpp.nix
    ./stable-diffusion-cpp.nix
    ./open-webui.nix
  ];
}
