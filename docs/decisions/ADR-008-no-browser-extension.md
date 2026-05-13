# ADR-008 — No browser extension, on any platform, ever

## Status
Accepted

## Context
Browser autofill on desktop platforms (Linux, Windows, macOS) is typically
delivered via a browser extension. Extensions run inside the browser process,
execute JavaScript, and communicate with a native host application via the
browser's Native Messaging API.

Several factors make this architecture incompatible with Gabbro's security
model and project values:

- **Supply chain attack surface.** Browser extensions are written in
  JavaScript and distributed via browser extension stores. The JavaScript
  ecosystem has a well-documented history of supply chain compromises —
  malicious packages injected into dependency trees, typosquatted modules,
  and maintainer account takeovers. A compromised extension runs with access
  to every page the user visits and every credential Gabbro would deliver
  through it. This is categorically more dangerous than a compromised library
  in a compiled binary.

- **In-process execution.** An extension runs inside the browser's renderer
  process, sharing memory space with page content. Any vulnerability in the
  extension — or in the browser's extension isolation boundary — creates a
  path from arbitrary web content to Gabbro credentials.

- **Maintenance burden.** Each major browser (Firefox, Chrome/Chromium,
  Brave, Safari) has its own extension API, manifest version requirements,
  and update cadence. Maintaining cross-browser compatibility is a
  significant ongoing engineering cost with no security benefit.

- **Threat model mismatch.** Gabbro is built for users with a high threat
  model — journalists, activists, privacy-conscious individuals. For these
  users, adding a JavaScript extension to the credential delivery path is not
  a reasonable trade-off, regardless of how carefully it is written.

- **Honest desktop UX.** On Linux and other desktop platforms, Gabbro
  provides copy-paste with clipboard auto-clear as the credential delivery
  mechanism. This is the same UX KeePass users have relied on for decades.
  It is not frictionless, but it is auditable, dependency-free, and
  compatible with Gabbro's threat model.

## Decision
Gabbro will never ship a browser extension on any platform. This applies
to v1, v2, and all future versions. It is not a resourcing decision; it is
a permanent security stance.

The desktop credential delivery model is: unlock Gabbro, copy the credential,
paste into the browser, clipboard auto-clears after the configured timeout.

## Consequences
- Desktop users do not get browser autofill. This is documented honestly
  in the README and any future marketing material.
- Users who require browser autofill on desktop should use 1Password,
  Bitwarden, or another provider that accepts the extension trade-off.
- The Native Messaging API is also excluded — it exists to support
  extensions and inherits the same threat model concerns.
- Gabbro's attack surface on desktop remains: the compiled Rust binary,
  the Flutter UI, and the vault file. No browser process involvement, no
  JavaScript runtime, no extension store dependency.
- Feature requests for a browser extension are closed as won't-fix with a
  pointer to this ADR.
