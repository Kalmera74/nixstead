# stable-diffusion.cpp

stable-diffusion.cpp provides local image and supported video generation.
Nixstead runs `sd-server` with the first-party `sdcpp-webui`, selects the CPU,
CUDA, or ROCm build, and waits for every configured model component.

## Enable and configure

```nix
nixstead.services.localai.stablediffusioncpp = {
  enable = true;
  domain = "stable.home.arpa";
  port = 1234;
  paths = {
    modelFile = "/mnt/models/stable-diffusion/model.safetensors";
    loraDir = "/mnt/models/stable-diffusion/loras";
  };
  settings."vae-tiling" = true;
};
```

For split image or video pipelines, set `paths.modelFile = null` and populate
`paths.modelFiles` with keys matching `sd-server` option names, such as
`diffusion-model`, `vae`, `t5xxl`, or `motion-module`. Arbitrary runtime flags
belong in `settings`; listener and typed path flags are managed by the module.

## Credentials and operation

The frontend at `https://stable.home.arpa` has no login. Video controls work only
when the loaded pipeline supplies the required video or motion components.
Inspect `stable-diffusion-cpp.service`; a missing configured model causes its
startup condition to skip the service. The HTTP listener opens only after a
compatible model loads successfully.

## State and recovery boundary

The baseline generation service reconstructs from configuration and model inputs.
Its checkpoint/components, LoRAs, embeddings and upscalers remain owned by the
model storage provider. Preserve unique assets there; reproducible downloads need
immutable hashes and an available licensed source. Nixstead does not automatically
archive every configured model path.

Generated images retained by a client belong to that client. If a deployment
retains server-side images/video or unique uploaded assets, name their output
paths and add a storage recovery policy before declaring persistence/recovery
inapplicable. Retained outputs are not proven disposable merely because the
current registry has no backup. CPU generation and valid-image checks need a
bounded fixture; no hardware acceleration claim follows from option evaluation.

## Dedicated checks

`service-stablediffusioncpp-config` evaluates selection, listener/path arguments,
split model requirements, managed-option conflicts, exposure and CPU group
settings on x86-64 and AArch64. Healthy native startup remains unverified in
the fast suite: `sd-server` loads a complete compatible model before opening
its HTTP listener, and no small compatible checkpoint fixture is available.
Model loading, generation and GPU tests are excluded to keep this check small.
The registry declares no automatic backup of externally owned model inputs.
