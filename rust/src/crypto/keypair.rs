//! Keypair derivation from KDF output.
//!
//! The 96-byte output of `derive_key()` is split into:
//!   bytes [0..32]  → X25519 private key
//!   bytes [32..96] → ML-KEM-1024 private key seed (64 bytes)
//!
//! Only X25519 is handled here. ML-KEM keypair derivation lives in the ml_kem
//! module.
//!
//! ## Version-dispatched derivation (RT-3)
//! Two derivation paths exist, selected by vault file version upstream:
//!   * **VERSION 10+ (`from_kdf_output_direct`)** — the secret scalar is bytes
//!     [0..32] used directly (clamping is applied by x25519 at DH time). No PRNG.
//!   * **VERSION 2–9 (`from_kdf_output_legacy`)** — the secret bytes are drawn
//!     from `StdRng::from_seed(kdf[0..32])`, exactly as every shipped build did.
//!
//! The legacy path routes through `rand::StdRng` (ChaCha12), whose byte stream is
//! **not** contracted stable across `rand` major versions. It is frozen here as a
//! compat-critical invariant so existing vaults still open — see the golden-value
//! test below and the backward-compat gate. **Do not** change the RNG, the seed
//! slice, or the fill order on the legacy path: doing so re-derives different keys
//! and permanently bricks every v2–9 vault.

use rand::rngs::StdRng;
use rand::{RngCore, SeedableRng};
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::Zeroizing;

/// An X25519 keypair derived from KDF output.
pub struct X25519Keypair {
    pub public: PublicKey,
    pub secret: StaticSecret,
}

impl X25519Keypair {
    /// VERSION 10+ derivation: use KDF bytes [0..32] directly as the secret
    /// scalar (clamped by x25519 at DH time), with no PRNG in the path.
    pub fn from_kdf_output_direct(kdf_output: &[u8; 96]) -> Self {
        let seed: Zeroizing<[u8; 32]> = Zeroizing::new(
            kdf_output[0..32]
                .try_into()
                .expect("slice is exactly 32 bytes"),
        );
        let secret = StaticSecret::from(*seed);
        let public = PublicKey::from(&secret);
        Self { public, secret }
    }

    /// Legacy VERSION 2–9 derivation: seed `StdRng` with KDF bytes [0..32] and
    /// take its first 32 output bytes as the secret scalar — byte-identical to the
    /// original `ReusableSecret::random_from_rng` construction (both store raw
    /// bytes and clamp at DH). Frozen: see the module docs and golden-value test.
    pub fn from_kdf_output_legacy(kdf_output: &[u8; 96]) -> Self {
        let seed: Zeroizing<[u8; 32]> = Zeroizing::new(
            kdf_output[0..32]
                .try_into()
                .expect("slice is exactly 32 bytes"),
        );
        let mut rng = StdRng::from_seed(*seed);
        let mut secret_bytes = Zeroizing::new([0u8; 32]);
        rng.fill_bytes(&mut *secret_bytes);
        let secret = StaticSecret::from(*secret_bytes);
        let public = PublicKey::from(&secret);
        Self { public, secret }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::kdf::{derive_key, Argon2idParams};

    fn test_params() -> Argon2idParams {
        Argon2idParams {
            m_cost: 4096,
            t_cost: 1,
            p_cost: 1,
        }
    }

    /// A fixed 96-byte KDF output (bytes 0,1,2,…) used by the golden-value pins.
    fn fixed_kdf_output() -> [u8; 96] {
        let mut kdf_output = [0u8; 96];
        for (i, b) in kdf_output.iter_mut().enumerate() {
            *b = i as u8;
        }
        kdf_output
    }

    #[test]
    fn legacy_keypair_derives_from_kdf_output() {
        let kdf_output = derive_key(b"passphrase", &[0u8; 32], &test_params()).unwrap();
        let keypair = X25519Keypair::from_kdf_output_legacy(&kdf_output);
        assert_ne!(keypair.public.as_bytes(), &[0u8; 32]);
    }

    #[test]
    fn legacy_derivation_is_deterministic() {
        let kdf_output = derive_key(b"passphrase", &[1u8; 32], &test_params()).unwrap();
        let a = X25519Keypair::from_kdf_output_legacy(&kdf_output);
        let b = X25519Keypair::from_kdf_output_legacy(&kdf_output);
        assert_eq!(a.public.as_bytes(), b.public.as_bytes());
    }

    #[test]
    fn different_passphrases_produce_different_legacy_keys() {
        let params = test_params();
        let out_a = derive_key(b"passphrase one", &[2u8; 32], &params).unwrap();
        let out_b = derive_key(b"passphrase two", &[2u8; 32], &params).unwrap();
        let a = X25519Keypair::from_kdf_output_legacy(&out_a);
        let b = X25519Keypair::from_kdf_output_legacy(&out_b);
        assert_ne!(a.public.as_bytes(), b.public.as_bytes());
    }

    /// S4 — golden-value pin for the LEGACY (v<=9) path. The `StdRng`-based
    /// derivation must produce these EXACT public-key bytes for a fixed KDF output.
    /// A `rand`/`x25519-dalek` bump that silently changes the key stream is caught
    /// here (it would otherwise brick every v<=9 vault), and the VERSION-10 refactor
    /// must leave this path byte-identical. Doubles as the Phase 5 tripwire seed.
    #[test]
    fn x25519_legacy_derivation_matches_frozen_golden_public_key() {
        let keypair = X25519Keypair::from_kdf_output_legacy(&fixed_kdf_output());
        const GOLDEN_PUBLIC: [u8; 32] = [
            144, 93, 1, 63, 6, 234, 162, 180, 92, 255, 17, 134, 180, 251, 100, 90, 216, 163, 187,
            209, 72, 97, 38, 52, 186, 26, 252, 161, 3, 68, 221, 122,
        ];
        assert_eq!(
            keypair.public.as_bytes(),
            &GOLDEN_PUBLIC,
            "legacy StdRng X25519 derivation drifted from the frozen golden value -- \
             a dependency bump changed the key stream; this WOULD brick every v<=9 vault"
        );
    }

    /// S1 — the v10 direct derivation is deterministic.
    #[test]
    fn direct_derivation_is_deterministic() {
        let kdf_output = derive_key(b"passphrase", &[3u8; 32], &test_params()).unwrap();
        let a = X25519Keypair::from_kdf_output_direct(&kdf_output);
        let b = X25519Keypair::from_kdf_output_direct(&kdf_output);
        assert_eq!(a.public.as_bytes(), b.public.as_bytes());
    }

    /// S2 — golden-value pin for the v10 DIRECT path, and proof it is the plain
    /// `clamp(kdf[0..32])` scalar with no PRNG: the derived key equals a public key
    /// built straight from `StaticSecret::from(kdf[0..32])`.
    #[test]
    fn x25519_direct_derivation_matches_frozen_golden_public_key() {
        let kdf_output = fixed_kdf_output();
        let keypair = X25519Keypair::from_kdf_output_direct(&kdf_output);
        const GOLDEN_PUBLIC: [u8; 32] = [
            143, 64, 197, 173, 182, 143, 37, 98, 74, 229, 178, 20, 234, 118, 122, 110, 201, 77,
            130, 157, 61, 123, 94, 26, 209, 186, 111, 62, 33, 56, 40, 95,
        ];
        assert_eq!(
            keypair.public.as_bytes(),
            &GOLDEN_PUBLIC,
            "v10 direct X25519 derivation drifted from its frozen golden value"
        );

        // No PRNG: identical to using the KDF bytes directly as the secret scalar.
        let seed: [u8; 32] = kdf_output[0..32].try_into().unwrap();
        let direct_public = PublicKey::from(&StaticSecret::from(seed));
        assert_eq!(
            keypair.public.as_bytes(),
            direct_public.as_bytes(),
            "v10 derivation must be clamp(kdf[0..32]) with no StdRng"
        );
    }

    /// S3 — the v10 direct path derives a DIFFERENT key from the legacy path for
    /// the same KDF output (the StdRng stream transforms the seed; direct does not).
    #[test]
    fn direct_derivation_differs_from_legacy_for_same_kdf() {
        let kdf_output = fixed_kdf_output();
        let direct = X25519Keypair::from_kdf_output_direct(&kdf_output);
        let legacy = X25519Keypair::from_kdf_output_legacy(&kdf_output);
        assert_ne!(
            direct.public.as_bytes(),
            legacy.public.as_bytes(),
            "v10 direct derivation must not alias the legacy StdRng key"
        );
    }
}
