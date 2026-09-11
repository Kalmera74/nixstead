# Stirling PDF

Stirling PDF provides browser-based PDF conversion, editing, OCR, and related
tools. Nixstead runs the native `stirling-pdf.service` on the registry endpoint.

## Enable and configure

```nix
nixstead.services.productivity.stirlingpdf = {
  enable = true;
  domain = "pdf.home.arpa";
  port = 8082;
};
```

The current module manages only enablement and the endpoint. Application-wide
settings not exposed by the module must be added to the implementation before
they become part of the supported host API.

The supported Nixstead profile leaves authentication and persistent user
settings disabled. PDF uploads, generated output and temporary files are
disposable processing data, so the service has no archive policy. Restarting it
or recreating `/var/lib/stirling-pdf` reconstructs the supported profile.

The native runtime suite is intentionally a fast startup/readiness smoke on the
configured loopback endpoint. Account mode, retained settings, document
operations, OCR/office conversion, large-document performance and cross-version
migration need separate evidence before they are supported.

## Credentials

This configuration does not enable Stirling PDF authentication or generate a
login. Restrict the endpoint through the network exposure policy. Inspect
`stirling-pdf.service` and its journal for conversion failures.
