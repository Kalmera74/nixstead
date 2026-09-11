{pkgs}:
pkgs.n8n.overrideAttrs (old: {
  # The non-redistributable native package must build locally. Bound build
  # parallelism while retaining the pinned source and production build commands.
  buildPhase =
    builtins.replaceStrings
    ["pnpm build --filter=n8n"]
    ["pnpm build --filter=n8n --concurrency=2"]
    old.buildPhase;
})
