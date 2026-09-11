"""Fast VM startup and recovery mechanics shared by service smoke tests."""

import shlex


class ServiceScenario:
    def __init__(
        self,
        machine,
        *,
        units,
        ready,
        populate,
        verify,
        erase,
        before_backup=lambda: None,
    ):
        self.machine = machine
        self.units = " ".join(shlex.quote(unit) for unit in units)
        self.ready = ready
        self.populate = populate
        self.verify = verify
        # Deliberately not derived from backup metadata: missing backup paths
        # must be observable when applications check their recovered content.
        self.erase = erase
        self.before_backup = before_backup
        self.environment = (
            "NIXSTEAD_REGISTRY_FILE=/etc/backup-registry.json "
            "NIXSTEAD_BACKUP_STATE_DIR=/var/lib/test-backups "
            "BORG_PASSPHRASE=disposable-service-suite"
        )

    def command(self, command):
        return self.environment + " " + command

    def run(self, phase):
        if phase not in {"runtime", "recovery"}:
            raise ValueError(f"Unknown service test phase: {phase}")
        try:
            self.ready()
            self.populate()
            self.verify()
            if phase == "recovery":
                self.before_backup()
                self.machine.succeed(self.command("nixstead-backup-service-configs"))
                # Backup restarts units it stopped. The clean restore is next,
                # so do not wait for a full application bootstrap just to stop
                # the same units again.
                self.machine.succeed(f"systemctl stop {self.units}")
                self.erase()
                # Exercise one real restore from the encrypted archive. This is
                # the useful wiring check; separate rehearsal, refusal and reboot
                # loops made every service suite repeat the same slow lifecycle.
                archive = self.machine.succeed(
                    self.command(
                        "borg list --short --last 1 /var/lib/test-backups/borg-service-data"
                    )
                ).strip()
                if not archive:
                    raise AssertionError("Backup did not produce a Borg archive")
                self.machine.succeed(
                    self.command(
                        "nixstead-restore-service-configs borg "
                        + shlex.quote(archive)
                        + " --apply --restore-databases --restart-services"
                    )
                )
                self.ready()
                self.verify()
        except Exception:
            # Best-effort diagnostics must never replace the original failure.
            for command in [
                # `status` includes child command lines; bootstrap CLIs may
                # accept credentials only through runtime arguments.
                f"systemctl show {self.units} --property=ActiveState,SubState,Result,ExecMainCode,ExecMainStatus",
                "journalctl -b --no-pager -n 120",
            ]:
                try:
                    self.machine.execute(command)
                except Exception:
                    pass
            raise
