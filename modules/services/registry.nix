let
  helpers = import ./registry/lib.nix;
in
  (import ./registry/arr.nix helpers)
  // (import ./registry/media.nix helpers)
  // (import ./registry/dev.nix helpers)
  // (import ./registry/localai.nix helpers)
  // (import ./registry/productivity.nix helpers)
  // (import ./registry/standalone.nix helpers)
  // (import ./registry/external.nix helpers)
  // (import ./registry/platform.nix helpers)
