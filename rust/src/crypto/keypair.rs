//! Keypair derivation from KDF output.
//!
//! The 96-byte output of `derive_key()` is split into:
//!   bytes [0..32]  → X25519 private key
//!   bytes [32..96] → ML-KEM-1024 private key seed (64 bytes)
//!
//! Only X25519 is handled here. ML-KEM keypair derivation lives in
//! the ml_kem module, which is added next.

use rand::rngs::StdRng;
use rand::SeedableRng;
use x25519_dalek::{PublicKey, ReusableSecret};
use zeroize::Zeroizing;

/// An X25519 keypair derived from KDF output.
pub struct X25519Keypair {
    pub public: PublicKey,
    pub secret: ReusableSecret,
}

impl X25519Keypair {
    /// Derives an X25519 keypair from bytes [0..32] of KDF output.
    pub fn from_kdf_output(kdf_output: &[u8; 96]) -> Self {
        let seed: Zeroizing<[u8; 32]> = Zeroizing::new(
            kdf_output[0..32]
                .try_into()
                .expect("slice is exactly 32 bytes"),
        );
        let mut rng = StdRng::from_seed(*seed);
        let secret = ReusableSecret::random_from_rng(&mut rng);
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

    #[test]
    fn x25519_keypair_derives_from_kdf_output() {
        let kdf_output = derive_key(b"passphrase", &[0u8; 32], &test_params()).unwrap();
        let keypair = X25519Keypair::from_kdf_output(&kdf_output);
        // public key is 32 bytes — just verify it is non-zero
        assert_ne!(keypair.public.as_bytes(), &[0u8; 32]);
    }

    #[test]
    fn x25519_keypair_is_deterministic() {
        let kdf_output = derive_key(b"passphrase", &[1u8; 32], &test_params()).unwrap();
        let a = X25519Keypair::from_kdf_output(&kdf_output);
        let b = X25519Keypair::from_kdf_output(&kdf_output);
        assert_eq!(a.public.as_bytes(), b.public.as_bytes());
    }

    #[test]
    fn different_passphrases_produce_different_x25519_keys() {
        let params = test_params();
        let out_a = derive_key(b"passphrase one", &[2u8; 32], &params).unwrap();
        let out_b = derive_key(b"passphrase two", &[2u8; 32], &params).unwrap();
        let a = X25519Keypair::from_kdf_output(&out_a);
        let b = X25519Keypair::from_kdf_output(&out_b);
        assert_ne!(a.public.as_bytes(), b.public.as_bytes());
    }

    /// Golden-value pin (net-first for RT-3). The current `StdRng`-based derivation
    /// must produce these EXACT public-key bytes for a fixed KDF output. This locks
    /// the legacy (v<=9) X25519 derivation byte-for-byte: a `rand`/`x25519-dalek`
    /// bump that silently changes the key stream is caught here (it would otherwise
    /// brick every existing vault), and the VERSION-10 refactor can prove it leaves
    /// this legacy path unchanged. Doubles as the seed for the Phase 5 tripwire.
    #[test]
    fn x25519_legacy_derivation_matches_frozen_golden_public_key() {
        let mut kdf_output = [0u8; 96];
        for (i, b) in kdf_output.iter_mut().enumerate() {
            *b = i as u8;
        }
        let keypair = X25519Keypair::from_kdf_output(&kdf_output);
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
}
