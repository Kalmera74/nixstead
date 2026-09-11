{
  stateful = true;
  paths = ["modules/services/nginx/"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Isolated native listeners and registry vhosts, child disable, backend isolation, renewal/secret ordering and rejected incomplete/store-key/invalid renewal CA settings.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    covers = ["runtime"];
    systems = ["x86_64-linux"];
    quick = true;
    detail = "Nginx, its generated local CA and a registry proxy start; an independent client trusts that CA, reaches the proxy and cannot reach the loopback backend directly.";
  };
  limitations = ["Local-CA archive recovery, rotation/retrust, repeated lifecycle, upstream failures, websocket behavior, external certificate authorities, ARM runtime and upgrades remain unverified by this fast smoke."];
}
