# Gabbro crack-me challenge

**Published:** 2026-07-11  
**Status:** Not cracked

`decryptMe_2026-07-11.gabbro` is a real Gabbro vault, sealed with a 
randomly-generated passphrase and two registered YubiKeys.

---

## The challenge

Decrypt the vault body and read the note inside. The note contains a field labelled as `decryptionProof_*` which is a random string.

## The reward

The first person to submit valid proof **before making it public** wins **two YubiKey keys**.

## How to submit

Email **gabbro@tuta.com** with:

0. The full character string from the vault note (`decryptionProof_*`, exact, character-for-character).
1. The master passphrase of the vault.
2. A description of the method used.

---

## What counts as proof

The vault body is encrypted with AES-256-GCM. The key is derived from both
the passphrase and the FIDO2 hmac-secret of a physical YubiKey. Finding the
passphrase alone is not sufficient: it recovers the `wrapping_key` from the
`passphrase_blob` header field, but the vault body remains locked behind the
YubiKey layer.

Valid proof means reproducing the exact character string from the vault
note. The character random string has high entropy (no entropy value is provided so as not to suggest what str lenght was used): guessing it is
not a viable strategy. Proof requires actually decrypting the vault, which
means bypassing the full crypto stack, not just Argon2id.

---

## Crypto stack

Full technical description: [`docs/SECURITY.md`](../docs/SECURITY.md).

Summary: Argon2id (m=64 MiB, t=25, p=4) → HKDF-SHA256 → second HKDF pass
combining the result with the YubiKey hmac-secret → AES-256-GCM.

---

## Notes

- This vault has not been externally audited. The challenge is intended to
  surface vulnerabilities in the implementation, not to claim it is proven
  secure. See [`docs/AI_SECURITY_AUDIT.md`](../docs/AI_SECURITY_AUDIT.md) for
  the known open questions (F-01, F-03).
- The "not cracked" status is updated manually. Check the git history of this
  file for the record.
