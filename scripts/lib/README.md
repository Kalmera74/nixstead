# Script library

`nixstead.sh` provides shared Bash helpers for evaluating one host's NixOS
configuration.

Callers set:

```bash
REPO_ROOT=/path/to/Nixstead
HOST_NAME=myhost
SECRETS_DIR=/path/to/secrets
```

Then source the library:

```bash
# shellcheck source=scripts/lib/nixstead.sh
source "${REPO_ROOT}/scripts/lib/nixstead.sh"
```

Available helpers build validated flake references and return raw/JSON option
values, attribute names, applied transformations, or boolean enabled state.
`nixstead_require_host` validates an explicit host before selecting a secrets
file. `nixstead_config_validate_context` also checks the flake directory; lookup
helpers call it automatically. Neither helper chooses a host implicitly.

Keep generic lookup behavior here. Service lists and metadata should come from
`nixstead.serviceRegistry`, not from hardcoded library tables.
