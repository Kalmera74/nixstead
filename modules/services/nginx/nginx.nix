{
  config,
  host,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixstead.services.nginx;
  caCfg = cfg.ca;

  nginxLib = import ./lib.nix {inherit lib;};

  caDir = "/var/lib/nginx/local-ca";
  caKey = "${caDir}/ca.key";
  caCert = "${caDir}/ca.crt";
  certsDir = nginxLib.tlsDir;
  managedUser = config.nixstead.host.user;
  managedUserGroup =
    if managedUser.enable
    then config.users.users.${managedUser.name}.group
    else "users";
  managedUserFilesDirectory =
    if managedUser.enable
    then "${config.users.users.${managedUser.name}.home}/${managedUser.generatedFilesDirectory}"
    else "";

  externalCaCert =
    if caCfg.certificateFile == null
    then ""
    else caCfg.certificateFile;
  externalCaKey =
    if caCfg.privateKeyFile == null
    then ""
    else caCfg.privateKeyFile;
  homeCaCert =
    if caCfg.homeCertificateFile == null
    then ""
    else caCfg.homeCertificateFile;
  legacyHomeCaCert =
    if managedUser.enable
    then "${config.users.users.${managedUser.name}.home}/${config.nixstead.host.hostName}-local-ca.crt"
    else "";
  renewBeforeSeconds = caCfg.renewBeforeDays * 24 * 60 * 60;

  enabledProxyDomains = lib.unique (map (entry: entry.settings.domain) (
    lib.attrValues (lib.filterAttrs (
        _: entry:
          entry.enabled
          && entry.proxy != null
          && entry.settings.domain != null
      )
      config.nixstead.serviceRegistry)
  ));

  generateLocalCaAndCerts = pkgs.writeShellScriptBin "generate-local-ca-and-certs" ''
    set -euo pipefail

    reload_nginx=false
    defer_missing_external=false
    for argument in "$@"; do
      case "$argument" in
        --reload-nginx) reload_nginx=true ;;
        --defer-missing-external) defer_missing_external=true ;;
        *) echo "Unknown argument: $argument" >&2; exit 2 ;;
      esac
    done

    ca_dir=${lib.escapeShellArg caDir}
    managed_ca_key=${lib.escapeShellArg caKey}
    managed_ca_crt=${lib.escapeShellArg caCert}
    certs_dir=${lib.escapeShellArg certsDir}
    external_ca_key=${lib.escapeShellArg externalCaKey}
    external_ca_crt=${lib.escapeShellArg externalCaCert}
    home_ca_crt=${lib.escapeShellArg homeCaCert}
    legacy_home_ca_crt=${lib.escapeShellArg legacyHomeCaCert}
    renew_before_seconds=${toString renewBeforeSeconds}
    certificates_changed=false

    ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g nginx "$ca_dir" "$certs_dir"
    exec 9>"$ca_dir/.renew.lock"
    ${pkgs.util-linux}/bin/flock -x 9

    temporary_dir="$(${pkgs.coreutils}/bin/mktemp -d "$ca_dir/.renew.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -rf "$temporary_dir"' EXIT

    public_keys_match() {
      local certificate="$1"
      local private_key="$2"

      ${pkgs.openssl}/bin/openssl x509 -in "$certificate" -pubkey -noout \
        >"$temporary_dir/certificate-public-key.pem" 2>/dev/null &&
        ${pkgs.openssl}/bin/openssl pkey -in "$private_key" -pubout \
          >"$temporary_dir/private-public-key.pem" 2>/dev/null &&
        ${pkgs.diffutils}/bin/cmp -s \
          "$temporary_dir/certificate-public-key.pem" \
          "$temporary_dir/private-public-key.pem"
    }

    valid_ca_certificate() {
      local certificate="$1"

      ${pkgs.openssl}/bin/openssl x509 -in "$certificate" -noout -checkend 0 \
        >/dev/null 2>&1 &&
        ${pkgs.openssl}/bin/openssl x509 -in "$certificate" -noout -text \
          | ${pkgs.gnugrep}/bin/grep -q 'CA:TRUE'
    }

    generate_ca_certificate() {
      local output="$temporary_dir/ca.crt"

      ${pkgs.openssl}/bin/openssl req -x509 -new \
        -key "$managed_ca_key" \
        -sha256 -days ${toString caCfg.validityDays} \
        -out "$output" \
        -subj ${lib.escapeShellArg "/CN=${caCfg.commonName}"} \
        -addext 'basicConstraints=critical,CA:TRUE' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' \
        -addext 'subjectKeyIdentifier=hash'

      ${pkgs.coreutils}/bin/install -m 0644 -o root -g nginx \
        "$output" "$temporary_dir/managed-ca.crt"
      ${pkgs.coreutils}/bin/mv -f "$temporary_dir/managed-ca.crt" "$managed_ca_crt"
      certificates_changed=true
    }

    if [ -n "$external_ca_crt" ]; then
      if [ ! -r "$external_ca_crt" ] || [ ! -r "$external_ca_key" ]; then
        if [ "$defer_missing_external" = true ]; then
          echo "External Nginx CA files are not available during activation; deferring to nginx-local-certificates.service" >&2
          exit 0
        fi
        echo "External Nginx CA certificate and private key must both be readable" >&2
        exit 1
      fi

      if ! valid_ca_certificate "$external_ca_crt"; then
        echo "External Nginx CA certificate is invalid, expired, or is not a CA" >&2
        exit 1
      fi
      if ! public_keys_match "$external_ca_crt" "$external_ca_key"; then
        echo "External Nginx CA certificate and private key do not match" >&2
        exit 1
      fi
      if ! ${pkgs.openssl}/bin/openssl x509 -in "$external_ca_crt" -noout \
        -checkend "$renew_before_seconds" >/dev/null 2>&1; then
        echo "Warning: the external Nginx CA expires within ${toString caCfg.renewBeforeDays} days; renew it at its source" >&2
      fi

      if [ ! -s "$managed_ca_crt" ] || ! ${pkgs.diffutils}/bin/cmp -s "$external_ca_crt" "$managed_ca_crt"; then
        ${pkgs.coreutils}/bin/install -m 0644 -o root -g nginx \
          "$external_ca_crt" "$temporary_dir/external-ca.crt"
        ${pkgs.coreutils}/bin/mv -f "$temporary_dir/external-ca.crt" "$managed_ca_crt"
        certificates_changed=true
      fi
      active_ca_key="$external_ca_key"
    else
      regenerate_ca_certificate=false

      if [ -e "$managed_ca_key" ]; then
        ${pkgs.coreutils}/bin/chown root:root "$managed_ca_key"
        ${pkgs.coreutils}/bin/chmod 0600 "$managed_ca_key"
      fi

      if ! ${pkgs.openssl}/bin/openssl pkey -in "$managed_ca_key" -noout >/dev/null 2>&1; then
        if [ -e "$managed_ca_crt" ]; then
          echo "The generated Nginx CA certificate exists but its private key is missing or invalid; refusing to rotate the trust anchor automatically" >&2
          exit 1
        fi
        umask 0077
        ${pkgs.openssl}/bin/openssl genrsa -out "$temporary_dir/ca.key" 4096
        ${pkgs.coreutils}/bin/install -m 0600 -o root -g root \
          "$temporary_dir/ca.key" "$temporary_dir/managed-ca.key"
        ${pkgs.coreutils}/bin/mv -f "$temporary_dir/managed-ca.key" "$managed_ca_key"
        regenerate_ca_certificate=true
      fi

      if ! valid_ca_certificate "$managed_ca_crt" ||
        ! public_keys_match "$managed_ca_crt" "$managed_ca_key" ||
        ! ${pkgs.openssl}/bin/openssl x509 -in "$managed_ca_crt" -noout \
          -checkend "$renew_before_seconds" >/dev/null 2>&1; then
        regenerate_ca_certificate=true
      fi

      if [ "$regenerate_ca_certificate" = true ]; then
        generate_ca_certificate
      fi
      active_ca_key="$managed_ca_key"
    fi

    active_ca_crt="$managed_ca_crt"
    ${pkgs.coreutils}/bin/chown root:nginx "$active_ca_crt"
    ${pkgs.coreutils}/bin/chmod 0644 "$active_ca_crt"

    issue_cert() {
      local domain="$1"
      local crt="$certs_dir/$domain.crt"
      local key="$certs_dir/$domain.key"
      local csr="$temporary_dir/$domain.csr"
      local ext="$temporary_dir/$domain.ext"
      local new_crt="$temporary_dir/$domain.crt"
      local new_key="$temporary_dir/$domain.key"
      local renew=true

      if [[ ! "$domain" =~ ^[A-Za-z0-9*._-]+$ ]]; then
        echo "Refusing unsafe TLS domain name: $domain" >&2
        exit 1
      fi

      if [ -s "$crt" ] && [ -s "$key" ] &&
        ${pkgs.openssl}/bin/openssl x509 -in "$crt" -noout \
          -checkend "$renew_before_seconds" >/dev/null 2>&1 &&
        ${pkgs.openssl}/bin/openssl x509 -in "$crt" -noout \
          -checkhost "$domain" >/dev/null 2>&1 &&
        ${pkgs.openssl}/bin/openssl verify -CAfile "$active_ca_crt" "$crt" \
          >/dev/null 2>&1 &&
        public_keys_match "$crt" "$key"; then
        renew=false
      fi

      if [ "$renew" = false ]; then
        ${pkgs.coreutils}/bin/chown root:nginx "$crt" "$key"
        ${pkgs.coreutils}/bin/chmod 0644 "$crt"
        ${pkgs.coreutils}/bin/chmod 0640 "$key"
        return
      fi

      umask 0027
      ${pkgs.openssl}/bin/openssl genrsa -out "$new_key" 4096
      ${pkgs.openssl}/bin/openssl req -new -key "$new_key" -out "$csr" -subj "/CN=$domain"

      ${pkgs.coreutils}/bin/printf '%s\n' \
        'basicConstraints=critical,CA:FALSE' \
        'keyUsage=critical,digitalSignature,keyEncipherment' \
        'extendedKeyUsage=serverAuth' \
        "subjectAltName=DNS:$domain" \
        >"$ext"

      ${pkgs.openssl}/bin/openssl x509 -req \
        -in "$csr" \
        -CA "$active_ca_crt" -CAkey "$active_ca_key" \
        -CAserial "$ca_dir/ca.srl" -CAcreateserial \
        -out "$new_crt" \
        -days ${toString caCfg.certificateValidityDays} -sha256 \
        -extfile "$ext"

      ${pkgs.openssl}/bin/openssl verify -CAfile "$active_ca_crt" "$new_crt" >/dev/null
      public_keys_match "$new_crt" "$new_key"

      ${pkgs.coreutils}/bin/install -m 0640 -o root -g nginx \
        "$new_key" "$temporary_dir/installed-$domain.key"
      ${pkgs.coreutils}/bin/install -m 0644 -o root -g nginx \
        "$new_crt" "$temporary_dir/installed-$domain.crt"
      ${pkgs.coreutils}/bin/mv -f "$temporary_dir/installed-$domain.key" "$key"
      ${pkgs.coreutils}/bin/mv -f "$temporary_dir/installed-$domain.crt" "$crt"
      certificates_changed=true
    }

    for domain in ${lib.escapeShellArgs enabledProxyDomains}; do
      issue_cert "$domain"
    done

    if [ -n "$home_ca_crt" ]; then
      home_ca_parent="$(${pkgs.coreutils}/bin/dirname "$home_ca_crt")"
      ${pkgs.coreutils}/bin/install -d -m 0700 \
        -o ${lib.escapeShellArg managedUser.name} \
        -g ${lib.escapeShellArg managedUserGroup} \
        "$home_ca_parent"
      if [ ! -s "$home_ca_crt" ] || ! ${pkgs.diffutils}/bin/cmp -s "$active_ca_crt" "$home_ca_crt"; then
        home_ca_temporary="$(${pkgs.coreutils}/bin/mktemp "$home_ca_parent/.local-ca.XXXXXX")"
        ${pkgs.coreutils}/bin/install -m 0644 \
          -o ${lib.escapeShellArg managedUser.name} \
          -g ${lib.escapeShellArg managedUserGroup} \
          "$active_ca_crt" "$home_ca_temporary"
        ${pkgs.coreutils}/bin/mv -f "$home_ca_temporary" "$home_ca_crt"
      fi
      if [ -n "$legacy_home_ca_crt" ] && [ "$legacy_home_ca_crt" != "$home_ca_crt" ] &&
        [ -f "$legacy_home_ca_crt" ] && ${pkgs.diffutils}/bin/cmp -s "$active_ca_crt" "$legacy_home_ca_crt"; then
        ${pkgs.coreutils}/bin/rm -f -- "$legacy_home_ca_crt"
      fi
    fi

    if [ "$certificates_changed" = true ] && [ "$reload_nginx" = true ] &&
      ${pkgs.systemd}/bin/systemctl is-active --quiet nginx.service; then
      # Avoid enqueueing a reload job while this required service is still
      # active; Nginx treats SIGHUP as its graceful configuration reload.
      ${pkgs.systemd}/bin/systemctl kill --kill-whom=main --signal=HUP nginx.service
    fi
  '';
in {
  options.nixstead.services.nginx = {
    enable = lib.mkEnableOption "Nginx reverse proxy";

    ca = {
      certificateFile = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "^/.*");
        default = null;
        example = "/etc/nixstead-ca/root-ca.crt";
        description = ''
          Absolute runtime path to an external CA certificate used to sign
          Nginx service certificates. Set privateKeyFile as well. This is a
          string rather than a Nix path so CA material is not copied to the
          Nix store.
        '';
      };

      privateKeyFile = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "^/.*");
        default = null;
        example = "/run/secrets/nixstead-ca-key";
        description = ''
          Absolute runtime path to the private key matching certificateFile.
          Keep this file root-readable and outside the Nix store.
        '';
      };

      commonName = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "${config.nixstead.host.hostName}-local-ca";
        description = "Common name used when generating the host-managed CA.";
      };

      validityDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3650;
        description = "Validity in days for the generated root CA certificate.";
      };

      certificateValidityDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 825;
        description = "Validity in days for generated service certificates.";
      };

      renewBeforeDays = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 30;
        description = "Renew generated certificates this many days before expiry.";
      };

      homeCertificateFile = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "^/.*");
        default =
          if managedUser.enable
          then "${managedUserFilesDirectory}/${config.nixstead.host.hostName}-nginx-ca.crt"
          else null;
        defaultText = lib.literalExpression ''
          if nixstead.host.user.enable
          then "<user-home>/<generatedFilesDirectory>/<hostname>-nginx-ca.crt"
          else null
        '';
        description = "User-accessible copy of the public CA certificate; null disables publication.";
      };
    };
  };

  imports = [
    ./registry-proxies.nix
  ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (caCfg.certificateFile == null) == (caCfg.privateKeyFile == null);
        message = "nixstead.services.nginx.ca.certificateFile and privateKeyFile must be set together.";
      }
      {
        assertion = caCfg.privateKeyFile == null || !lib.hasPrefix "/nix/store/" caCfg.privateKeyFile;
        message = "nixstead.services.nginx.ca.privateKeyFile must not point into the world-readable Nix store.";
      }
      {
        assertion = caCfg.renewBeforeDays < caCfg.certificateValidityDays;
        message = "nixstead.services.nginx.ca.renewBeforeDays must be less than certificateValidityDays.";
      }
      {
        assertion = caCfg.certificateFile != null || caCfg.renewBeforeDays < caCfg.validityDays;
        message = "nixstead.services.nginx.ca.renewBeforeDays must be less than validityDays for the generated CA.";
      }
      {
        assertion = caCfg.homeCertificateFile == null || managedUser.enable;
        message = "Publishing the Nginx CA to a home directory requires nixstead.host.user.enable.";
      }
    ];

    services.nginx = {
      enable = true;
      defaultHTTPListenPort = config.nixstead.host.ports.http;
      defaultSSLListenPort = config.nixstead.host.ports.https;
    };

    system.activationScripts.local-ca-and-certs = {
      deps = ["users" "groups"];
      text = ''
        ${generateLocalCaAndCerts}/bin/generate-local-ca-and-certs \
          --defer-missing-external \
          --reload-nginx
      '';
    };

    systemd.services = {
      nginx = {
        after = ["nginx-local-certificates.service"];
        requires = ["nginx-local-certificates.service"];
      };

      nginx-local-certificates = {
        description = "Renew Nginx local TLS certificates";
        before = ["nginx.service"];
        after = ["sops-install-secrets.service"];
        serviceConfig.Type = "oneshot";
        script = ''
          ${generateLocalCaAndCerts}/bin/generate-local-ca-and-certs --reload-nginx
        '';
      };
    };

    systemd.timers.nginx-local-certificates = {
      description = "Daily renewal check for Nginx local TLS certificates";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
        Unit = "nginx-local-certificates.service";
      };
    };
  };
}
