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
}
