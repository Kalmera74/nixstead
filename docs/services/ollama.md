# Ollama

Ollama serves local large-language models through its native API. Nixstead
runs `ollama.service`, binds it through the registry, and selects acceleration
from `nixstead.host.hardware.gpu.acceleration`.

## Enable and configure

```nix
nixstead.services.localai.ollama = {
  enable = true;
  domain = "ollama.home.arpa";
  port = 11434;
  paths.modelsDir = "/mnt/models/ollama";
};
```

`paths.modelsDir` is optional; when unset, the native NixOS location is used.
Changing it does not copy existing manifests or blobs. Pull and list models on
the host with `ollama pull <model>` and `ollama list`.

## Credentials and clients

The local API has no application login. Open WebUI can use it automatically, or
clients can target `https://ollama.home.arpa`. Keep exposure private unless an
authentication layer is added. Inspect `ollama.service` and `journalctl -u
ollama` for model-loading or GPU errors.

## State and recovery boundary

Downloaded models are reproducible only when their exact artifacts, manifests,
license and acquisition source remain available. Record immutable model hashes
and acquisition instructions outside the cache. Re-pulling a mutable tag is not
proof that the same model was reconstructed.

Unique imported weights, custom model definitions and locally created adapters
are owned durable assets. Their storage owner must back up the effective native
models directory (manifests and referenced blobs together) plus any source
Modelfiles or unique inputs outside it. Nixstead does not currently provide an
Ollama archive policy or a passing storage-owner recovery fixture. Keep P/B open
for that profile; do not classify all model state as disposable.

## Startup smoke

`service-ollama-runtime` starts native Ollama with a custom model directory,
checks its loopback listener and reads the version endpoint. Model import,
inference, model persistence, restart/reboot, registries, GPU/ARM execution and
cross-version compatibility remain outside this fast smoke. Unique imported
models, definitions and adapters still need their own storage-owner backup and
restore policy.
