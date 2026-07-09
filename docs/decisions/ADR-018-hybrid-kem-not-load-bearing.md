# ADR-018: The Hybrid KEM Layer Is Not Load-Bearing

## Status
Accepted

## Date
2026-07-09

## Context

External review (Cryptography Stack Exchange, 2026-07-08, comment by
poncho) confirmed a design-level fact about the X25519 + ML-KEM-1024
hybrid layer ("double lock") that prior ADRs got wrong.

**Why the layer exists:** "post-quantum password manager" was the
project's founding identity (initial commit, 2026-03-18). ADR-006
inherited ML-KEM as an unexamined premise and added X25519, justified
by "vault secure if either ML-KEM or X25519 holds". Nobody asked the
obvious question first: can the passphrase alone open the vault?

**Why that claim is empty:** both keypairs are re-derived from the
same Argon2id output, i.e. from the passphrase.
- Attacker *with* a passphrase guess: re-derives both keypairs and
  bypasses the layer entirely. Guessing is the only real attack.
- Attacker *without* the passphrase: cannot even attack the layer —
  neither public key is stored in the file. The vault stays secure
  even if *both* algorithms are broken.
In no scenario does vault security depend on X25519 or ML-KEM. The
layer is structure, not strength.

**What actually makes Gabbro quantum-resistant:** Argon2id + AES-256.
Quantum computers break key-exchange math; they barely help with
passphrase guessing, and AES-256 resists them. Gabbro is quantum-safe
the same way KeePass/Bitwarden are — via the symmetric stack. ML-KEM
is quantum-resistant math doing a job that did not need doing.

**Passphrase-only mode** (added after ADR-006, which assumed a
mandatory YubiKey): exactly as strong as the passphrase, no more.
Argon2id is the only brute-force defence. Passphrase + YubiKey mode
is sound: the YubiKey's hmac-secret is an independent physical secret,
mixed into the vault key downstream of the hybrid layer.

**What the layer does deliver:** a fresh vault key per save (from the
encapsulation/ephemeral randomness) — achievable with a random HKDF
salt alone. It is also pre-built plumbing for a future genuinely
independent second secret (keyfile, secure element), but every such
secret conflicts with the copy-the-file portability model, so this
optionality is expensive to ever cash in.

**Industry hybrid guidance** (TLS, Signal, iMessage) answers "should
PQ key exchange be paired with classical?" — yes. It does not answer
"should a passphrase-unlocked file format contain key exchange at
all?". Two-party recommendations do not transfer to one secret
re-derived on one device.

## Decision

1. Reclassify the hybrid layer as non-load-bearing structure. All
   "belt and suspenders" / "secure if either holds" claims are
   retracted; living docs (ARCHITECTURE, SECURITY, README, diagrams)
   to be corrected to attribute quantum resistance to Argon2id +
   AES-256-GCM.
2. Keep the layer for now — removal is a vault-format change and the
   Stack Exchange question ("can it make things *worse* than
   HKDF(KM)?") is still open. Revisit keep-vs-remove when it
   concludes.
3. ADR-006 marked superseded. ADR-005 marked amended: its side-claim
   that "the PQ claim rests on ML-KEM + AES-256-GCM" is corrected by
   this ADR (its actual decision — ML-DSA over hybrid signatures —
   stands). Note:
   ADR-006's "cheap passphrase change via random session key K" was
   never implemented; passphrase change is a full reseal.

## References

- https://crypto.stackexchange.com/questions/119762/
- ADR-005, ADR-006
