# Installation and update validation

Use a fresh disposable NixOS VM and an independent client. Do not use production
secrets or disks. Follow the [setup guide](setup-wizard.md) and record any missing
instructions or manual interventions needed to complete the journey.

For each trial, record date, CPU architecture, RAM, source NixOS release,
original stateVersion, repository and Nixpkgs revisions, and these results:

| Step | Evidence to record |
| --- | --- |
| Generate configuration | `./setup.sh --generate-only`; alternate checkout/imported stateVersion using `--state-version`; generated host evaluates |
| Install and first login | Console recovery available; user can log in over SSH using chosen authentication; confirm NetworkManager and locale changes |
| DNS and HTTPS | Independent client resolves chosen domain; certificate fails before CA trust and succeeds afterward; direct backend port is inaccessible |
| Credentials | Create administrator; authenticated API/browser access; runtime credentials readable only by intended users |
| Persistent data | Upload or create meaningful content, record its identifier and checksum, then reboot and read it |
| Update | Record starting/ending locked revisions and migration notes; activate deliberately in the VM and verify login/content again |
| Restore | Back up; erase disposable app/database state; restore with the shipped helper; authenticate and compare content after reboot |

Record pass/fail, relevant redacted logs, documentation issues, and any help
needed. No manual trial results are recorded yet. The automated media starter VM
covers boot, SSH, DNS, CA trust, Jellyfin onboarding/restore and reboot with test
fixtures; it does not cover the interactive wizard, a real router/DNS setup,
a media download pipeline, or a cross-version upgrade trial.
