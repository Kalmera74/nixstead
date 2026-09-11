{
  stateful = false;
  paths = ["modules/services/media/tdarr.nix" "modules/services/media/tdarr-node.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent node/server selection, custom identity/data/cache/media paths, mount permissions and rejected missing identity; no local HTTP card or backup.";
  };
  checks.runtime = {
    file = ../tdarr/recovery.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "Native worker startup within the shared Tdarr server recovery smoke, with workers paused; the alias adds no separate VM.";
  };
  notApplicable = {
    persistence = "This worker owns no durable application records; its runtime/cache is reconstructed.";
    recovery = "Disposable worker state is reconstructed; server state and source bytes belong to separate owners.";
    upgrade = "This worker has no durable application-state migration; compatibility across revisions remains unverified.";
  };
  limitations = ["Real server reconnect and CPU job safety require the server/node integration fixture; node cache is disposable."];
}
