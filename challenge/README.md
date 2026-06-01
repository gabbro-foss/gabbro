# Gabbro crack-me challenge

**Published:** 2026-06-01  
**Status:** Not cracked

`decryptMe_2026-06-01.gabbro` is a real Gabbro vault, sealed with a 256-character
randomly-generated passphrase and two registered YubiKeys.

---

## The challenge

Decrypt the vault body and read the note inside. The note contains a single
512-character random string.

## The reward

The first person to submit valid proof wins **two YubiKey keys**.

## How to submit

Email **gabbro.app@gmail.com** with:

0. The full 512-character string from the vault note (exact, character-for-character).
1. The master passphrase of the vault.
2. A description of the method used.

---

## What counts as proof

The vault body is encrypted with AES-256-GCM. The key is derived from both
the passphrase and the FIDO2 hmac-secret of a physical YubiKey. Finding the
passphrase alone is not sufficient: it recovers the `wrapping_key` from the
`passphrase_blob` header field, but the vault body remains locked behind the
YubiKey layer.

Valid proof means reproducing the exact 512-character string from the vault
note. A 512-character random string has ~2996 bits of entropy: guessing it is
not a viable strategy. Proof requires actually decrypting the vault, which
means bypassing the full crypto stack, not just Argon2id.

---

## Crypto stack

Full technical description: [`docs/SECURITY.md`](../docs/SECURITY.md).

Summary: Argon2id (m=64 MiB, t=25, p=4) → X25519 + ML-KEM-1024 hybrid key
exchange → HKDF-SHA256 → second HKDF pass combining the result with the
YubiKey hmac-secret → AES-256-GCM.

---

## Notes

- This vault has not been externally audited. The challenge is intended to
  surface vulnerabilities in the implementation, not to claim it is proven
  secure. See [`docs/AI_SECURITY_AUDIT.md`](../docs/AI_SECURITY_AUDIT.md) for
  the known open questions (F-01, F-03).
- The "not cracked" status is updated manually. Check the git history of this
  file for the record.
