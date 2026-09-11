{lib}: let
  registry = import ../modules/services/registry.nix;
  suites = import ./services {inherit lib;};
  categories = ["configuration" "runtime" "persistence" "recovery" "failure" "upgrade"];
  relative = file: lib.removePrefix (toString ../. + "/") (toString file);
  dedicatedChecks = lib.foldlAttrs (all: id: suite:
    all
    // lib.mapAttrs' (phase: check:
      lib.nameValuePair "service-${id}-${phase}" {
        services = [id];
        paths = ["tests/services/${id}/"] ++ suite.paths;
        tier =
          if phase == "config"
          then "fast"
          else "runtime";
        systems = check.systems or ["x86_64-linux" "aarch64-linux"];
        executionKey = relative check.file;
        quick = check.quick or false;
        weight = check.weight or 1;
        inherit (check) detail;
      })
    suite.checks) {}
  suites;
  checks =
    dedicatedChecks
    // {
      python = {
        services = ["vaultwarden" "redis" "paperless" "sonarr" "qbittorrent" "homepage" "seerr" "arr-integrations" "tubearchivist"];
        paths = [];
        tier = "fast";
        detail = "Shared process/unit fixtures for credentials, reconciliation and backup helpers, including real Redis RDB validation, Vaultwarden SQLite snapshots and Elasticsearch snapshot protocol/archive refusal; no full application recovery claim.";
      };
      public-module-api = {
        services = builtins.attrNames registry;
        paths = ["tests/public-api.nix"];
        tier = "fast";
        detail = "Shared registry/public API assertions; does not establish every isolated service contract.";
      };
    };
  services =
    lib.mapAttrs (id: entry: let
      suite = suites.${id} or {};
      phaseChecks = category:
        lib.mapAttrsToList (phase: _: "service-${id}-${phase}")
        (lib.filterAttrs (_: check: lib.elem category check.covers) (suite.checks or {}));
      coverage = lib.genAttrs categories (category: let
        evidence = phaseChecks category;
        reason = (suite.notApplicable or {}).${category} or null;
      in
        {
          status =
            if evidence != []
            then "scenario"
            else if reason != null
            then "not-applicable"
            else if category == "configuration"
            then "shared"
            else "missing";
          checks =
            if evidence != []
            then evidence
            else lib.optional (category == "configuration" && reason == null) "public-module-api";
        }
        // lib.optionalAttrs (reason != null) {inherit reason;});
    in {
      inherit (entry) name local;
      inherit coverage;
      stateful =
        suite.stateful or (
          if entry.backup != null
          then true
          else null
        );
      support = suite.support or "limited";
      suite =
        if suites ? ${id}
        then "tests/services/${id}/default.nix"
        else null;
      paths = suite.paths or [];
      relatedChecks = builtins.attrNames (lib.filterAttrs (_: check: lib.elem id check.services) checks);
      limitations =
        (suite.limitations or [])
        ++ lib.optional (!(suites ? ${id})) "No dedicated service suite; shared checks do not establish the full service contract."
        ++ lib.optional (!entry.local) "Externally hosted endpoint; no external system is started or recovered here."
        ++ lib.optional (!(coverage.upgrade.status == "scenario")) "No test changes between pinned application revisions.";
    })
    registry;
  invalidSuites = lib.attrNames (lib.filterAttrs (_: suite:
    !(
      suite.checks
      != {}
      && suite.checks ? config
      && lib.all (category: lib.elem category categories && suite.notApplicable.${category} != "") (builtins.attrNames (suite.notApplicable or {}))
      && lib.all (
        phase: let
          check = suite.checks.${phase};
        in
          builtins.pathExists check.file
          && check.covers != []
          && check.detail != ""
          && (phase == "config" || check ? systems)
          && lib.all (category: lib.elem category categories) check.covers
      ) (builtins.attrNames suite.checks)
    ))
  suites);
in
  assert lib.assertMsg (lib.all (id: registry ? ${id}) (builtins.attrNames suites)) "Test suite has no matching service registry entry";
  assert lib.assertMsg (invalidSuites == []) "Invalid service suites (${lib.concatStringsSep ", " invalidSuites}): config check, existing files, explicit runtime architectures, known coverage categories and descriptions are required"; {
    schemaVersion = 1;
    inherit categories checks services;
  }
