# Homepage

Homepage is the generated service dashboard. Nixstead builds cards from the
central registry, orders them by section, injects optional widget credentials
through a SOPS environment file, and accepts host-specific shortcuts.

## Enable and configure

```nix
nixstead.services.homepage = {
  enable = true;
  domain = "home.home.arpa";
  port = 2525;
  disabledWidgets = ["grafana"];
  shortcuts = [
    {
      name = "NixOS";
      href = "https://nixos.org";
      icon = "nixos";
      description = "NixOS project";
    }
  ];
};
```

`disabledWidgets` keeps a service card but omits that card's widget and secret
requirements. Populate API keys after applications are initialized with
`nixstead --host <host> credentials configure homepage`.

## Credentials

Homepage itself has no login in this configuration. Widget secrets are runtime
integration credentials, not Homepage credentials. Inspect
`homepage-dashboard.service` and its generated environment template.

## Runtime coverage and state boundary

Homepage has no independent application database in this profile. Its dashboard
is reconstructed from declarative registry data, while SOPS owns widget
credentials. The disposable `service-homepage-runtime` check renders a real
shortcut and TrueNAS card and calls the bounded peer's authenticated status and
alert endpoints once. Configuration checks cover the generated placeholder and
listener/proxy selection. Credential rotation, dependency failures and repeated
restart/reboot behavior are outside the maintained fast smoke.
