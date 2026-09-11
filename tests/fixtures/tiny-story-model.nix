{pkgs}:
pkgs.fetchurl {
  name = "stories15M-q4_0.gguf";
  url = "https://huggingface.co/ggml-org/models-moved/resolve/499bc8821c6b12b4e53c5bffcb21ec206f212d81/tinyllamas/stories15M-q4_0.gguf";
  hash = "sha256-ZpZ/vs5tvpeIZZP9u3NYlYSSfikRnsMfCAkHMtGGFzk=";
  meta.license = pkgs.lib.licenses.mit;
}
