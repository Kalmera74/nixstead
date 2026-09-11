# Core options

`options.nix` defines the typed `nixstead.host` interface, generic service-option
helpers, and the resolved read-only `nixstead.serviceRegistry` view.

Service stack wrappers receive these module arguments:

- `serviceRegistry` — static registry metadata;
- `serviceOption` — generic endpoint-option constructor; and
- `serviceOptionFromRegistry` — constructor populated from one registry entry.

Example use in a stack:

```nix
options.nixstead.services.media.example =
  serviceOptionFromRegistry "example" {};
```

Host-specific identity and network values belong in `nixstead.host`; do not introduce
parallel host-variable structures. See
[Configuring a host](../../docs/configuration.md).
