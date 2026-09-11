# llama.cpp

llama.cpp exposes a single GGUF model through `llama-server`. Nixstead can
resolve an installed Ollama model from Ollama's blob store or pass arbitrary
server settings such as a Hugging Face repository.

## Enable and configure

```nix
nixstead.services.localai.llamacpp = {
  enable = true;
  domain = "llama.home.arpa";
  port = 8084;
  ollamaModel = "qwen3:8b";
  settings."ctx-size" = 8192;
};
```

When `ollamaModel` is set, local Ollama must also be enabled and the named model
must already be installed. Alternatively leave it null and use `settings`, for
example `settings."hf-repo"`. Host and port are registry-managed and should not
be repeated in `settings`.

## Credentials and operation

The server and OpenAI-compatible API have no login in this configuration.
Inspect `llama-cpp.service` and its journal when the unit is waiting for a model
or cannot initialize the selected GPU backend.

## State and recovery boundary

The baseline server reconstructs transient inference state from its declared
settings and read-only model inputs. The storage owner preserves unique GGUF and
projector bytes or records a reproducible immutable download. Ollama-backed mode
uses a read-only bind of that server's manifests/blobs and delegates their recovery
to the Ollama model owner. No independent inference-state archive is promised.

Any additional flags that retain unique outputs or a writable cache with durable
content create an additional ownership profile.

## Startup smoke

`service-llamacpp-runtime` starts the native server with the pinned 19 MB
TinyStories fixture, checks the configured loopback listener and waits for its
health endpoint. The model is an immutable configuration-owned input. Inference
semantics, model-loss behavior, restart/reboot, production model quality,
GPU/ARM execution, unique input/output backup and cross-version compatibility
remain outside this fast smoke.
