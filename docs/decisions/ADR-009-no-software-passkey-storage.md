# ADR-009: No Software Passkey Storage

## Status

Accepted

## Date

2026-05-15 (created); 2026-06-22 (edited)

## Context

Passkey managers such as Bitwarden store FIDO2 private keys encrypted in the
vault, acting as a software authenticator — intercepting WebAuthn credential
creation, generating the key pair in software, and storing the private key in
the encrypted vault. The question arose whether Gabbro should do the same.

## Decision

Gabbro will not implement software passkey storage, now or in future versions.

## Rationale

Gabbro supports and strongly recommends a FIDO2 hardware key (YubiKey) for vault
access (ADR-010), though a passphrase-only vault is also allowed. A user who opts
into hardware-key protection already possesses a passkey authenticator that is
strictly stronger than software storage.

The security distinction is codified in NIST SP 800-63B-4, which defines
Authenticator Assurance Levels (AALs):

> "Since syncable authenticators require the private key to be exportable,
> syncable authenticators SHALL NOT be used at AAL3. Cryptography used by
> verifiers at AAL3 SHALL be validated at FIPS 140 Level 1 or higher.
> Hardware-based authenticators and verifiers at AAL3 SHOULD resist relevant
> side-channel attacks."
>
> — NIST SP 800-63B-4, Section 4.3

In plain terms: hardware-bound passkeys qualify for AAL3, the highest assurance
level. Synced or software-stored passkeys are capped at AAL2 because the private
key must be exportable to function. A software passkey stored in Gabbro's vault,
however well-encrypted, lives in the same threat model as the vault itself — it
does not provide the hardware-isolation guarantee a YubiKey does.

Yubico's own documentation confirms that hardware security keys isolate
cryptographic keys from the host OS and software, protecting them from most
forms of compromise — a property that software storage cannot replicate.

Adding software passkey storage would therefore offer Gabbro's users a *weaker*
credential type than the hardware they already own and are required to possess.

**Implementation cost** is also high: Android `CredentialManager` API
(Android 14+), CTAP2 protocol handling, and browser extension integration for
desktop — with no net security benefit for the target user.

## Consequences

- No `Passkey` entry type.
- No `CredentialManager` integration.
- This decision is permanent, not deferred.

## References

- NIST SP 800-63B-4: <https://pages.nist.gov/800-63-4/sp800-63b.html>
- Yubico on FIDO2 and AAL3: <https://www.yubico.com/authentication-standards/fido2/>
- ADR-005: YubiKey / FIDO2 hardware authentication requirement
