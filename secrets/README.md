# Encrypted host secrets

Tracked `*.yaml` host files in this directory are encrypted with SOPS. The
plaintext [schema](secrets.example.yaml) contains placeholders only.

```text
secrets/
├── secrets.example.yaml  # tracked schema; never real values
└── <host>.yaml           # tracked SOPS ciphertext
```

Quick start:

```bash
nix shell path:.#setup-runtime
export SOPS_AGE_KEY_FILE="$HOME/.local/share/nixstead/sops-age-key.txt"
./scripts/configure-sops-host.sh <host>
NIXSTEAD_HOST=<host> ./scripts/generate-credential-files.sh all
sops secrets/<host>.yaml
```

NixOS decrypts declared keys to `/run/secrets` during activation. See
[Secrets and credentials](../docs/secrets.md) for the threat model, external
directory override, migration, rotation, and recovery workflow.
