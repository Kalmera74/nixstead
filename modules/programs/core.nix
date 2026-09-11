{pkgs, ...}: {
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
    herdr
    zip
    unzip
    stow
    dysk
  ];
}
