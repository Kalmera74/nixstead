# RabbitMQ

RabbitMQ is an AMQP message broker. Nixstead runs the native
`rabbitmq.service`, provisions an administrator from SOPS, grants full `/`
virtual-host permissions, and removes the default `guest` account when a
different administrator name is used.

## Enable and configure

```nix
nixstead.services.dev.rabbitmq = {
  enable = true;
  port = 5672;
};
```

Port 5672 is the AMQP listener; the repository does not enable RabbitMQ's
management web UI. Generate credentials with
`nixstead --host <host> credentials bootstrap devdb`.

## Credentials

```bash
sudo cat /run/secrets/devdb/rabbitmq/rootUser
sudo cat /run/secrets/devdb/rabbitmq/rootPassword
```

Inspect it with `systemctl status rabbitmq` and `journalctl -u rabbitmq`.

The bootstrap uses the runtime SOPS template and passes passwords to
`rabbitmqctl` over standard input. Restarting the broker applies an updated
encrypted administrator password while retaining other accounts and queues.

## Recovery

The registered backup stops the broker and captures the native data directory,
including definitions, durable messages and the Erlang cookie. Restore refuses
an archive missing `.erlang.cookie` before changing the running broker. Restore
with the same node name, package revision and encrypted bootstrap source. A
custom `services.rabbitmq.dataDir` remains inside this snapshot boundary.

The maintained x86_64 fixture checks native startup/readiness and one shipped
Borg backup/restore with an independent test-owned continuity marker. It erases
the declared application root and checks the marker after final readiness.
Business workflows, repeated lifecycle and failure matrices are outside this
smoke fixture. The combined startup/recovery check passed in 119.19 seconds.
Configuration is checked independently on x86_64 and aarch64.

Run the focused suites with:

```bash
nix build --no-link -L path:.#checks.x86_64-linux.service-rabbitmq
```

The smoke uses a local single-node broker. Queue/account workflows, clustered,
quorum and stream recovery, external authentication backends, changed node names,
cross-version upgrades and exactly-once delivery remain unverified. Retain the
encrypted SOPS source and decryption identity separately; they are not inside
the application archive. ARM currently has configuration checks only.

See the [development recovery contracts](../../modules/services/dev/README.md#recovery-ownership)
for the surrounding services' ownership boundaries.
