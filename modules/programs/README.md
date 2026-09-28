# Program groups

Program modules install optional command-line tools independently from service
presets. Hosts import only the groups they want.

Packages use the stable NixOS 26.05 input. The core group explicitly selects
`herdr` from the separate locked unstable input because stable does not include
it. The public core export supplies that package set automatically; repository
hosts receive it through the shared default module.

| Module | Purpose |
| --- | --- |
| `core.nix` | Editors, Git, search, archive, terminal, and inspection tools |
| `development.nix` | Compilers, Nix tooling, Node.js, and coding assistants |
| `hardware.nix` | PCI, USB, and hardware inspection |
| `networking.nix` | NetworkManager and network utilities |
| `media.nix` | FFmpeg, HandBrake, yt-dlp, and media utilities |
| `backup.nix` | BorgBackup |
| `zsh.nix` | Zsh, Oh My Zsh, and repository-aware aliases |
| `yazi.nix` | Yazi plus editor environment variables |

Repo-local host imports:

```nix
imports = [
  ../../modules/programs/core.nix
  ../../modules/programs/networking.nix
  ../../modules/programs/zsh.nix
];
```

External consumers should import the matching public exports beside
`nixosModules.default`, for example:

```nix
modules = [
  nixstead.nixosModules.default
  nixstead.nixosModules.program-core
  nixstead.nixosModules.program-networking
  nixstead.nixosModules.program-zsh
  ./configuration.nix
];
```

The Zsh rebuild aliases depend on accurate `nixstead.host.repositoryPath` and
`nixstead.host.configurationName` values.
