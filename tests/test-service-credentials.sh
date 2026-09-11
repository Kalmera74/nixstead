#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/bin-no-sops" "${TEST_ROOT}/secrets"
touch "${TEST_ROOT}/secrets/testhost.yaml"

cat >"${TEST_ROOT}/runtime-password" <<'EOF'
runtime-secret
EOF

cat >"${TEST_ROOT}/miniflux.env" <<'EOF'
ADMIN_USERNAME=feed-admin
ADMIN_PASSWORD=password=with=equals
EOF

jq -n \
  --arg runtime_password "${TEST_ROOT}/runtime-password" \
  --arg miniflux_env "${TEST_ROOT}/miniflux.env" \
  '{
    nextcloud: {
      enabled: true,
      settings: {adminPasswordFile: null},
      credentials: [{
        label: "Admin password",
        source: {kind: "file", path: $runtime_password, pathOption: ["adminPasswordFile"], suffix: "", envKey: null}
      }],
      homepage: {widget: {secrets: {token: "nextcloudToken"}}}
    },
    miniflux: {
      enabled: false,
      settings: {adminCredentialsFile: null},
      credentials: [
        {
          label: "Username",
          source: {kind: "file", path: $miniflux_env, pathOption: ["adminCredentialsFile"], suffix: "", envKey: "ADMIN_USERNAME"}
        },
        {
          label: "Password",
          source: {kind: "file", path: $miniflux_env, pathOption: ["adminCredentialsFile"], suffix: "", envKey: "ADMIN_PASSWORD"}
        }
      ],
      homepage: null
    },
    openwebui: {
      enabled: false,
      settings: {environmentFile: null},
      credentials: [{
        label: "email",
        source: {
          kind: "file",
          path: null,
          pathOption: ["environmentFile"],
          envKey: "WEBUI_ADMIN_EMAIL",
          fallbackValue: null,
          optional: true
        }
      }],
      homepage: null
    }
  }' >"${TEST_ROOT}/registry.json"

cat >"${TEST_ROOT}/secrets.json" <<'EOF'
{
  "homepage": {"nextcloudToken": "homepage-secret"},
  "custom": {"unregistered": "unregistered-secret"}
}
EOF

cat >"${TEST_ROOT}/bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat "${FAKE_REGISTRY_JSON}"
EOF

cat >"${TEST_ROOT}/bin-no-sops/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ " $* " == *" shell "* ]]; then
  while [[ $# -gt 0 && "$1" != "--command" ]]; do
    shift
  done
  [[ $# -gt 0 ]] || exit 1
  shift
  PATH="${FAKE_RUNTIME_BIN}:${PATH}" exec "$@"
fi

cat "${FAKE_REGISTRY_JSON}"
EOF

cat >"${TEST_ROOT}/bin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

expression=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --extract)
      expression="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -z "${expression}" ]]; then
  cat "${FAKE_SECRETS_JSON}"
  exit 0
fi

case "${expression}" in
  '["homepage"]["nextcloudToken"]') printf '%s' 'homepage-secret' ;;
  '["custom"]["unregistered"]') printf '%s' 'unregistered-secret' ;;
  *)
    printf 'unknown test expression: %s\n' "${expression}" >&2
    exit 1
    ;;
esac
EOF

chmod +x "${TEST_ROOT}/bin/nix" "${TEST_ROOT}/bin-no-sops/nix" "${TEST_ROOT}/bin/sops"

for command_name in bash basename cat dirname jq; do
  ln -s "$(command -v "${command_name}")" "${TEST_ROOT}/bin-no-sops/${command_name}"
done

export FAKE_REGISTRY_JSON="${TEST_ROOT}/registry.json"
export FAKE_SECRETS_JSON="${TEST_ROOT}/secrets.json"
export FAKE_RUNTIME_BIN="${TEST_ROOT}/bin"
export PATH="${TEST_ROOT}/bin:${PATH}"

credential_script="${REPO_ROOT}/scripts/service-credentials.sh"
common_args=(--host testhost --secrets-dir "${TEST_ROOT}/secrets")

list_output="$("${credential_script}" "${common_args[@]}" list)"
grep -Fq $'service:nextcloud\tenabled\t2 source(s)' <<<"${list_output}"
grep -Fq 'sops:custom/unregistered' <<<"${list_output}"
if grep -Fq 'unregistered-secret' <<<"${list_output}"; then
  printf 'list unexpectedly revealed a secret value\n' >&2
  exit 1
fi

nextcloud_output="$("${credential_script}" "${common_args[@]}" show nextcloud)"
grep -Fq 'Admin password: runtime-secret' <<<"${nextcloud_output}"
grep -Fq 'Homepage token: homepage-secret' <<<"${nextcloud_output}"

miniflux_output="$("${credential_script}" "${common_args[@]}" show miniflux)"
grep -Fq 'Username: feed-admin' <<<"${miniflux_output}"
grep -Fq 'Password: password=with=equals' <<<"${miniflux_output}"

openwebui_output="$("${credential_script}" "${common_args[@]}" show openwebui)"
grep -Fq 'email: not preseeded' <<<"${openwebui_output}"

sops_output="$("${credential_script}" "${common_args[@]}" show sops:custom/unregistered)"
grep -Fq 'sops:custom/unregistered: unregistered-secret' <<<"${sops_output}"

automatic_runtime_output="$(
  PATH="${TEST_ROOT}/bin-no-sops" \
    "${credential_script}" "${common_args[@]}" show sops:custom/unregistered
)"
grep -Fq 'sops:custom/unregistered: unregistered-secret' <<<"${automatic_runtime_output}"

printf 'service credential tests passed\n'
