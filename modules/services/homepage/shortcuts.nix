{
  lib,
  shortcuts,
}: let
  iconBase = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png";
  resolveIcon = icon:
    if lib.hasSuffix ".png" icon && !(lib.hasPrefix "http://" icon || lib.hasPrefix "https://" icon)
    then "${iconBase}/${icon}"
    else icon;
in
  lib.optional (shortcuts != []) {
    Shortcuts =
      map (shortcut: {
        "${shortcut.name}" = {
          inherit (shortcut) description href;
          icon = resolveIcon shortcut.icon;
        };
      })
      shortcuts;
  }
