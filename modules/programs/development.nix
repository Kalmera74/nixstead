{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    gcc
    clang
    alejandra
    nil
    python3
    go
    nodejs
    lazygit
    opencode
    codex
  ];
}
