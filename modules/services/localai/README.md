# Local AI stack

This directory provides Ollama, llama.cpp, stable-diffusion.cpp, and Open WebUI.

```nix
nixstead.services.localai = {
  enable = true;
  ollama.enable = true;
  llamacpp.enable = true;
  stablediffusioncpp.enable = true;
  openwebui.enable = true;
};
```

The parent defaults all children on, while explicit child values can override
it. The `full` preset selects this stack. GPU capability is configured
separately through `nixstead.host.hardware.gpu.acceleration`.

Ollama uses its native model directory by default. To store downloads on a
different filesystem, configure an absolute path. Ollama waits for that
filesystem and llama.cpp mounts the same model directory read-only when it
reuses an Ollama model:

```nix
nixstead.services.localai.ollama.paths.modelsDir = "/mnt/public/LLM/Models";
```

llama.cpp starts in router mode when no model setting is provided. Configure a
Hugging Face GGUF model or a local models directory through native server
settings, for example:

```nix
nixstead.services.localai.llamacpp.settings = {
  "hf-repo" = "Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M";
  "ctx-size" = 4096;
};
```

To reuse an installed Ollama model without copying its GGUF blobs, select it by
name. llama.cpp resolves the current blob paths whenever its service starts:

```nix
nixstead.services.localai.llamacpp.ollamaModel = "qwen3.8:latest";
```

stable-diffusion.cpp runs `sd-server` with its first-party web frontend. A full
checkpoint defaults to `/var/lib/stable-diffusion-cpp/models/model.safetensors`.
The unit waits for that file instead of failing when the full preset is first
enabled. Point it at an existing checkpoint to use another location:

```nix
nixstead.services.localai.stablediffusioncpp = {
  enable = true;
  paths.modelFile = "/srv/models/stable-diffusion/sd-v1-5.safetensors";
  settings = {
    threads = 8;
    "vae-tiling" = true;
  };
};
```

The frontend enables generation modes reported by the loaded pipeline. Add an
SD 1.5 AnimateDiff motion module to a compatible full checkpoint to expose
video generation:

```nix
nixstead.services.localai.stablediffusioncpp.paths = {
  modelFile = "/srv/models/stable-diffusion/sd-v1-5.safetensors";
  modelFiles."motion-module" = "/srv/models/animatediff/mm_sd_v15_v2.ckpt";
};
```

For split-component pipelines such as Wan, LTX, Flux, or Qwen Image, set
`modelFile = null` and declare path-taking `sd-server` arguments in
`modelFiles`. Every file is included in the unit's mount and existence checks:

```nix
nixstead.services.localai.stablediffusioncpp = {
  paths = {
    modelFile = null;
    modelFiles = {
      "diffusion-model" = "/srv/models/wan/wan2.1-t2v-1.3b.safetensors";
      vae = "/srv/models/wan/wan_2.1_vae.safetensors";
      t5xxl = "/srv/models/wan/umt5-xxl-encoder-Q8_0.gguf";
    };
  };
  settings = {
    "diffusion-fa" = true;
    "offload-to-cpu" = true;
  };
};
```

Keys in `modelFiles` are passed to `sd-server` without restricting the model
family, so any component supported by the selected package can be used.
Listener, frontend, and model-directory arguments remain registry-managed.

Open WebUI requires an Ollama endpoint. When `ollama.enable = false`, set
`openwebui.ollamaUrl` to an external HTTP endpoint; otherwise evaluation fails.
