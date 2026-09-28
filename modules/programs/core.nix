{
  pkgs,
  pkgsUnstable,
  ...
}: {
  environment.systemPackages = with pkgs; [
    zsh
    vim
    neovim
    git
    fzf
    fd
    ripgrep
    jq
    trash-cli
    nvd
    ncdu
    tmux
    # herdr is not packaged in NixOS 26.05.
    pkgsUnstable.herdr
    zip
    unzip
    stow
    dysk
  ];
}
