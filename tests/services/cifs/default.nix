{
  stateful = false;
  paths = ["modules/services/cifs/"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Isolated native authenticated automount, custom ownership/read-only options and runtime private credentials; empty shares and duplicate mounts rejected; no local SMB server.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "A real Samba peer and the native CIFS automounts start with runtime SOPS authentication, and both configured shares return the expected bytes over CIFS.";
  };
  limitations = ["Remote content recovery belongs to the server. Credential rotation, peer loss, reboot reconnect, write policy, backup destination/server-loss recovery, cross-version upgrades and ARM runtime remain unverified."];
}
