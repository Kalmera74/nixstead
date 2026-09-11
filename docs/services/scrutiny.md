# Scrutiny

Scrutiny collects SMART data and presents drive-health history. Nixstead runs
the native Scrutiny web service, a local InfluxDB instance, and the Scrutiny
collector on a daily schedule.

## Enable and configure

```nix
nixstead.services.scrutiny = {
  enable = true;
  domain = "scrutiny.home.arpa";
  port = 8192;
  influxdbPort = 8086;
};
```

The collector discovers host block devices; individual disks do not need to be
listed in this Nix option. State directories are fixed at `/var/lib/scrutiny`
and `/var/lib/influxdb2`. Device visibility and SMART support still depend on
the underlying hardware and kernel.

## Credentials and operation

This configuration does not add a Scrutiny web login. Inspect
`scrutiny.service`, `scrutiny-collector.service`, its timer, and
`influxdb2.service` when data is missing.

## State and recovery boundary

Drive history requires `/var/lib/scrutiny` and `/var/lib/influxdb2` together.
The registry lists both paths and quiesces `scrutiny.service` and
`influxdb2.service` before staging. A Scrutiny-only directory archive cannot
establish historical-data recovery. Preserve hardware-independent collector
identity in the declarative host configuration.

## Dedicated checks

Configuration checks cover independent selection, configured listeners, collector
wiring, fixed paths and the combined backup policy. One combined smoke check starts
native Scrutiny and InfluxDB and checks their health responses and loopback ports.
It then runs the shipped Borg tools, erases both native state
directories, restores them, and checks readiness plus independent test-owned file
markers in both roots.

This checks Nixstead startup and backup wiring. SMART report ingestion, historical
metrics, physical disk access, repeated lifecycle and outage scenarios remain
outside the fixture. Runtime and recovery run on x86_64; ARM has configuration
evaluation only. Configuration passed on both architectures. The combined native
x86_64 startup and clean Borg recovery check passed with KVM in
56.15 seconds with Scrutiny 0.9.3 and InfluxDB 2.7.12.
