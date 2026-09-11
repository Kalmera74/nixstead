{
  mkSystem,
  lib,
  ...
}: let
  isolated = {
    nixstead.services.arr = {
      sonarr.enable = true;
      prowlarr.enable = true;
      integrations.prowlarr.sonarr.enable = true;
    };
  };
  config = (mkSystem [isolated]).config;
  disabled = (mkSystem [isolated {nixstead.services.arr.integrations.prowlarr.sonarr.enable = lib.mkForce false;}]).config;
  parent = (mkSystem [{nixstead.services.arr.enable = true;}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [isolated override]).config.assertions;
in {
  validSystem = builtins.isString (mkSystem [isolated]).config.system.build.toplevel.drvPath;
  selectedRelationshipEnablesReconciler = config.nixstead.serviceRegistry.arr-integrations.enabled && config.systemd.services ? nixstead-arr-reconcile && config.systemd.timers ? nixstead-arr-reconcile;
  targetDisableRemovesReconciler = !disabled.nixstead.serviceRegistry.arr-integrations.enabled && !(disabled.systemd.services ? nixstead-arr-reconcile) && !(disabled.systemd.timers ? nixstead-arr-reconcile);
  stackDoesNotOptIntoReconciliation = !parent.nixstead.services.arr.integrations.active && !(parent.systemd.services ? nixstead-arr-reconcile);
  selectedTargetsOnly = lib.elem "sonarr.service" config.systemd.services.nixstead-arr-reconcile.requires && lib.elem "prowlarr.service" config.systemd.services.nixstead-arr-reconcile.requires && !lib.elem "radarr.service" config.systemd.services.nixstead-arr-reconcile.requires;
  noStorageMutation = !config.nixstead.services.arr.storage.manageDirectories;
  privateOwnershipJournal = config.systemd.services.nixstead-arr-reconcile.serviceConfig.StateDirectory == "nixstead-arr-integrations" && config.systemd.services.nixstead-arr-reconcile.serviceConfig.StateDirectoryMode == "0700" && config.systemd.services.nixstead-arr-reconcile.serviceConfig.User == "nixstead-arr-reconcile";
  runtimeCredentials = config.systemd.services.nixstead-arr-reconcile.serviceConfig.LoadCredential == ["prowlarr:/run/nixstead-credentials/prowlarr/api-key" "sonarr:/run/nixstead-credentials/sonarr/api-key"];
  backupJournalAndQuiescing = config.nixstead.serviceRegistry.arr-integrations.backup.paths == ["/var/lib/nixstead-arr-integrations"] && config.nixstead.serviceRegistry.arr-integrations.backup.requiredFiles == ["ownership.json"] && config.nixstead.serviceRegistry.arr-integrations.backup.units == ["nixstead-arr-reconcile.timer" "nixstead-arr-reconcile.service"];
  noListenerOrCard = config.nixstead.serviceRegistry.arr-integrations.proxy == null && config.nixstead.serviceRegistry.arr-integrations.homepage == null && config.nixstead.serviceRegistry.arr-integrations.listeners.settingsTcpPorts == [];
  missingApplicationRejected = rejects "Prowlarr registration for sonarr requires" {nixstead.services.arr.sonarr.enable = lib.mkForce false;};
  missingStorageRejected = rejects "qbittorrentToSonarr requires" {nixstead.services.arr.integrations.qbittorrentToSonarr.enable = true;};
  missingCredentialBrokerRejected = rejects "ARR integration requires shared runtime credentials" {nixstead.services.arr.credentials.enable = lib.mkForce false;};
  defaultRelocationRefused = config.nixstead.services.arr.integrations.relocation == "refuse";
  customDryRunAccepted =
    (mkSystem [
      isolated
      {
        nixstead.services.arr.integrations = {
          dryRun = true;
          relocation = "allow";
        };
      }
    ]).config.nixstead.services.arr.integrations.dryRun;
  invalidSyncPolicyRejected = !(builtins.tryEval (mkSystem [isolated {nixstead.services.arr.integrations.prowlarr.sonarr.syncLevel = "overwrite-all";}]).config.nixstead.services.arr.integrations.prowlarr.sonarr.syncLevel).success;
}
