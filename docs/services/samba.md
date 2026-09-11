# Samba

Samba exports only explicitly selected directories to authenticated local users.
Enabling the NAS parent or `samba.enable` exports no directories by default.
There is no automatic tank, Public, Media or Backups share.

```nix
users.users.alice.isNormalUser = true;
nixstead.services.nas.samba = {
  enable = true;
  shares.Media = {
    path = "/srv/nas/Media";
    users = ["alice"];
    readOnly = true; # default; set false deliberately to permit writes
  };
};
```

The directory must already exist and its filesystem permissions must permit the
selected user's access. Nixstead does not create it or change its ownership.
Samba can be used independently of NAS disks. Choose LAN exposure explicitly
through `nixstead.host.network.exposure.services.samba` and the host's LAN
interface/source policy; enabling a share does not make public access necessary.

Provision each user's Samba password at runtime with `sudo smbpasswd -a alice`.
A Unix login password does not automatically create a Samba password. Test with
`smbclient //localhost/Media -U alice`; guest access and unlisted users are denied.
Inspect `samba-smbd.service` for failures. Preserve Samba's account database through
a separate policy or re-enroll passwords after disaster recovery; these service
changes do not advertise Samba account-database backups.

Existing guest-share users must select paths and users explicitly when upgrading.
Writable shares require `readOnly = false`. The former defaults are not retained
as a compatibility mode.

## State and recovery boundary

The baseline identity recovery flow is explicit password re-enrollment. Recreate
the declarative Unix users with stable UIDs/GIDs, reapply the explicit shares,
then provision their Samba passwords at runtime. The maintained access smoke
starts native Samba, writes and reads one exact file as an authenticated user,
and verifies that a configured read-only share rejects writes. It does not prove
password re-enrollment after lost account storage. Preserving the account
database and server identity requires a separate backup and restore fixture.

Share bytes belong to the backing storage owner. Neither declaring a share nor
restoring an account restores its files. A local NAS profile needs tested file
recovery; externally mounted shares need their server's recovery contract. Keep
unowned directories and file ownership unchanged during identity recovery.
Credential rotation, missing backing mounts, restart/reboot, ARM runtime and
upgrades remain outside the fast smoke.
