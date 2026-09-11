# Disposable encrypted source generated inside the VM before sops-nix runs.
# The generator prints JSON only into sops' stdin; no credential enters a store
# fixture or the test driver's output.
{
  pkgs,
  generator,
}: {lib, ...}: {
  nixstead.secrets = {
    enable = true;
    sopsFile = "/var/lib/service-fixture/secrets.yaml";
    age = {
      keyFile = "/var/lib/service-fixture/identity";
      sshKeyPaths = [];
    };
  };
  sops.validateSopsFiles = lib.mkForce false;
  system.activationScripts.service-fixture-secrets = {
    deps = ["specialfs"];
    text = ''
      (
        set -euo pipefail
        umask 077
        install -d -m 0700 /var/lib/service-fixture
        if [ ! -s /var/lib/service-fixture/identity ]; then
          ${pkgs.age}/bin/age-keygen -o /var/lib/service-fixture/identity
        fi
        if [ ! -s /var/lib/service-fixture/secrets.yaml ]; then
          recipient=$(${pkgs.age}/bin/age-keygen -y /var/lib/service-fixture/identity)
          ${pkgs.python3}/bin/python3 ${generator} generate | \
            ${pkgs.sops}/bin/sops encrypt --age "$recipient" --input-type json --output-type yaml /dev/stdin \
            > /var/lib/service-fixture/secrets.yaml
        fi
      )
    '';
  };
  system.activationScripts.setupSecrets.deps = ["service-fixture-secrets"];
  environment.systemPackages = [pkgs.age pkgs.sops pkgs.python3];
}
