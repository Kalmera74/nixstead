{config, ...}: let
  cfg = config.nixstead.host.locale;
in {
  time.timeZone = cfg.timeZone;

  i18n.defaultLocale = cfg.defaultLocale;
  i18n.extraLocaleSettings = cfg.extraLocaleSettings;

  console.keyMap = cfg.consoleKeyMap;
}
