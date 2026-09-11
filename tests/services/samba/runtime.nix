{
  pkgs,
  publicModules,
}:
pkgs.testers.runNixOSTest {
  name = "nixstead-samba-access";
  node.pkgsReadOnly = false;
  requiredFeatures.kvm = false;
  nodes = {
    server = {
      imports = [publicModules.nas];
      system.stateVersion = "26.05";
      users.users.alice = {isNormalUser = true;};
      nixstead.services.nas.samba = {
        enable = true;
        shares = {
          selected = {
            path = "/srv/selected";
            users = ["alice"];
            readOnly = false;
          };
          readonly = {
            path = "/srv/readonly";
            users = ["alice"];
          };
        };
      };
      nixstead.host.network.exposure.services.samba = "public";
      systemd.tmpfiles.rules = ["d /srv/selected 0700 alice users -" "d /srv/readonly 0700 alice users -"];
      environment.systemPackages = [pkgs.samba];
    };
    client = {
      system.stateVersion = "26.05";
      environment.systemPackages = [pkgs.samba];
    };
  };
  testScript = ''
    start_all()
    server.wait_for_unit("samba-smbd.service")
    server.succeed("printf 'vm-password\\nvm-password\\n' | smbpasswd -s -a alice")
    client.succeed("printf 'SMB startup fixture' > /tmp/payload")
    share = "//server/selected"
    client.succeed(f"smbclient {share} -U alice%vm-password -c 'put /tmp/payload data; get data /tmp/readback'")
    client.succeed("cmp /tmp/payload /tmp/readback")
    client.fail("smbclient //server/readonly -U alice%vm-password -c 'put /tmp/payload denied'")
  '';
}
