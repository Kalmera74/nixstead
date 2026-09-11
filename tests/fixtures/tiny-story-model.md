# Bounded CPU inference model

The fixture uses `stories15M-q4_0.gguf`, 19,077,344 bytes, at immutable
ggml-org revision `499bc8821c6b12b4e53c5bffcb21ec206f212d81`. Its SHA-256 is
`66967fbece6dbe97886593fdbb73589584927e29119ec31f08090732d1861739`.
The [upstream file and commit](https://huggingface.co/ggml-org/models-moved/commit/499bc8821c6b12b4e53c5bffcb21ec206f212d81)
record this content hash and the model's 128-token training context.

This quantization comes from the [TinyLlamas model family](https://huggingface.co/karpathy/tinyllamas),
which its author declares MIT licensed. The author's
[llama2.c project](https://github.com/karpathy/llama2.c) describes the 15M model
trained on TinyStories. The [ggml-org collection](https://huggingface.co/ggml-org/models-moved/blob/main/README.md)
provides models for llama.cpp CI and explicitly excludes production use.

Tests keep a 128-token context and bounded generated tokens. They establish
actual model loading, token generation, response validity, lifecycle and
failure behavior. They make no claim about useful assistant quality, GPUs,
large-model capacity, or model upgrades. The immutable archive belongs to the
fixture's configuration, while runtime copies and caches are reconstructible.
