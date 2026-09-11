{
  config,
  homepageSecrets,
  lib,
  ...
}: let
  sectionOrder = ["Arr" "Media" "Dev Tools" "OTEL" "Datastores" "Local AI" "Productivity" "Standalone" "Infrastructure"];

  registeredCards = lib.mapAttrs (id: entry: entry // {homepageServiceId = id;}) (
    lib.filterAttrs (_: entry: entry.enabled && entry.homepage != null) config.nixstead.serviceRegistry
  );

  cardsForSection = section: let
    entries = lib.filterAttrs (_: entry: entry.homepage.section == section) registeredCards;
    sorted = lib.sort (left: right: left.homepage.order < right.homepage.order) (lib.attrValues entries);

    renderCard = entry: let
      settings = entry.settings;
      card = entry.homepage;
      hrefHost =
        if card.hrefScheme == "tcp"
        then
          if settings.ip != null
          then settings.ip
          else "127.0.0.1"
        else settings.domain;
      hrefPort = lib.optionalString (card.hrefScheme == "tcp") ":${toString settings.port}";
      href = "${card.hrefScheme}://${hrefHost}${hrefPort}${card.hrefSuffix or ""}";

      widget =
        if lib.elem entry.homepageServiceId config.nixstead.services.homepage.disabledWidgets
        then null
        else card.widget or null;
      widgetTarget =
        if widget == null
        then null
        else if widget.target or "service" == "loopback"
        then "127.0.0.1"
        else if entry.local && entry.exposure == "lan" && config.nixstead.host.network.lan != null
        then config.nixstead.host.network.lan
        else if entry.local && entry.exposure == "tailnet" && config.nixstead.host.network.tailscale != null
        then config.nixstead.host.network.tailscale
        else if entry.local
        then "127.0.0.1"
        else if settings.ip != null
        then settings.ip
        else "127.0.0.1";
      widgetSecrets =
        if widget == null
        then {}
        else lib.mapAttrs (_: secretName: homepageSecrets.${secretName}) (widget.secrets or {});
      widgetConfig =
        if widget == null
        then null
        else
          {
            inherit (widget) type;
            url = "${widget.scheme or "http"}://${widgetTarget}:${toString settings.port}";
          }
          // (widget.extra or {})
          // widgetSecrets;
    in {
      "${card.title}" =
        {
          inherit (card) icon description;
          inherit href;
        }
        // lib.optionalAttrs (widgetConfig != null) {widget = widgetConfig;};
    };

    hostCards = lib.optionals (section == "Infrastructure") (
      lib.optional (config.nixstead.host.network.router != null) {
        Router = {
          icon = "router";
          description = "Gateway";
          href = "http://${config.nixstead.host.network.router}";
        };
      }
      ++ lib.optional (config.nixstead.host.network.switch != null) {
        Switch = {
          icon = "https://cdn.jsdelivr.net/gh/selfhst/icons@main/png/tp-link.png";
          description = "Switch";
          href = "http://${config.nixstead.host.network.switch}";
        };
      }
    );
    cards = map renderCard sorted ++ hostCards;
  in
    lib.optional (cards != []) {"${section}" = cards;};
in
  lib.concatMap cardsForSection sectionOrder
