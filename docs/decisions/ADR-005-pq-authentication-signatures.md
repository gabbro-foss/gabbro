# ADR-005: Post-Quantum Authentication — Pure ML-DSA-44

## Status
Accepted

## Date
2026-04-09

## Context

Gabbro uses FIDO2/WebAuthn hardware keys (YubiKey) as the sole
authentication mechanism (Layer 2). When implementing this layer,
we must choose a digital signature algorithm.

The default for FIDO2/WebAuthn is ECDSA over P-256, a classical
elliptic curve scheme. The options considered were:
- ECDSA/P-256 alone (classical)
- A hybrid classical + post-quantum scheme (e.g. ECDSA + ML-DSA)
- Pure ML-DSA-44 (post-quantum only)

### Threat landscape (April 2026)

Two papers published in late March / early April 2026 significantly
revised the estimated resource requirements for cryptographically-
relevant quantum computers (CRQCs):

1. Google revised downward the number of logical qubits needed to
   break 256-bit elliptic curves, making the attack feasible in
   minutes on superconducting architectures.
2. Oratomic showed 256-bit elliptic curves can be broken with as few
   as 10,000 physical qubits given non-local connectivity.

Cryptographer Filippo Valsorda (maintainer of Go's cryptography
standard library) updated his public position on 2026-04-06, citing
Google and Heather Adkins placing a 2029 deadline on CRQC readiness
— 33 months from now. His conclusion: "It makes no more sense to
deploy new schemes that are not post-quantum."

### Why not hybrid authentication?

For key *exchange*, hybrid classical+PQ is reasonable: ephemeral
keys are cheap to compose and the hedge has low cost.

For *authentication* (signatures), hybrid is the wrong tradeoff:
- It costs significant time and protocol complexity budget
- The only benefit is protection if ML-DSA is classically broken
  *before* a CRQC arrives — now assessed as the unlikely path
- Two years of production use of Module-Lattice schemes has built
  confidence in their security
- ML-DSA-44 and ML-KEM are approved at Top Secret level by the NSA
  for all national security purposes
- Composite signature drafts (draft-ietf-lamps-pq-composite-sigs-15)
  define 18 composite key types — complexity with no benefit for a
  greenfield project with no legacy compatibility requirement

### ML-DSA-44 vs ML-DSA-65 / ML-DSA-87

ML-DSA-44 is NIST Security Level 2. The higher parameter sets
(Level 3 and Level 5) produce larger signatures for a security
margin beyond what any known or anticipated attack requires.
Level 2 already has sufficient margin above Level 1 to absorb
minor cryptanalytic improvements. The extra bytes of Level 3/5
are not justified.

### Hardware support gap

Current YubiKey 5 series hardware (as of April 2026) supports
Ed25519 and ECDSA for FIDO2, but not ML-DSA. Gabbro's v1 release
timeline (weeks to months) cannot depend on Yubico shipping
PQ-capable hardware. Hardware key authentication is non-negotiable
for a password manager — shipping without it to wait for PQ
hardware would be the wrong tradeoff.

## Decision

Gabbro's authentication layer targets **pure ML-DSA-44** for all
digital signatures. No classical signature algorithm will be used
in the authentication path once PQ-capable hardware is available.

**Interim (v1):** FIDO2 credentials will use Ed25519 — the
strongest available classical option on current YubiKey hardware.
The auth layer will be designed for a clean migration to ML-DSA-44
when Yubico ships PQ-capable hardware or firmware. This migration
will require a credential re-registration flow for existing users.

The key exchange layer (ML-KEM-768, hybrid with classical) is
unaffected by this decision — see the Encryption Stack section
of ARCHITECTURE.md.

## Consequences

### Positive
- Hardware key authentication ships in v1; security posture is
  not compromised waiting for PQ hardware
- Authentication layer is designed for ML-DSA-44 from the start —
  migration is a credential re-registration, not an architectural
  change
- No protocol complexity from composite/hybrid key types
- Aligned with Valsorda's April 2026 guidance and NSA approval
- The PQ claim for Gabbro v1 rests honestly on the encryption
  stack (ML-KEM + AES-256-GCM); the authentication gap is
  documented rather than hidden

### Negative / Tradeoffs
- v1 authentication (Ed25519) is not quantum-resistant. This is
  a known, documented, hardware-constrained gap — not a design
  choice. Mitigated by the fact that the vault encryption layer
  is fully PQ.
- ML-DSA-44 signatures are ~2.4 KB vs ~64 bytes for Ed25519.
  Acceptable for local authentication challenges; not a
  performance concern for Gabbro's use case.
- Migration to ML-DSA-44 will require a credential re-registration
  flow. This must be designed before the migration ships — users
  must re-tap their YubiKey to create a new PQ credential.
- Minimum YubiKey firmware version for ML-DSA-44 support is not
  yet known; must be determined and documented when Yubico
  publishes PQ support.

## References

- Filippo Valsorda, "A Cryptography Engineer's Perspective on
  Quantum Computing Timelines", 2026-04-06:
  https://words.filippo.io/crqc-timeline/
- Google Research, "Safeguarding Cryptocurrency by Disclosing
  Quantum Vulnerabilities Responsibly", 2026:
  https://research.google/blog/safeguarding-cryptocurrency-by-disclosing-quantum-vulnerabilities-responsibly/
- Oratomic paper (arXiv:2603.28627):
  https://arxiv.org/abs/2603.28627
- NIST FIPS 204 (ML-DSA standard)
- NSA CNSA 2.0 suite — ML-KEM and ML-DSA approved at Top Secret
  level for all national security purposes