{
  stateful = false;
  paths = ["modules/services/external.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Remote HTTPS endpoint, websocket/self-signed proxy, card/token placeholders, disabled removal, invalid port and absence of local upstream/firewall/state.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "Homepage and a self-signed bounded Proxmox HTTPS peer start, and the widget returns the configured cluster resources using runtime SOPS API-token credentials.";
  };
  limitations = ["The peer implements only the cluster/resources endpoint used by the Homepage widget. Credential rotation, dependency failures, restart/reboot, live Proxmox compatibility, browser login, external VM/container backup, ARM runtime and upgrades are outside this smoke."];
}
