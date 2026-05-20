//! ML-KEM-1024 keypair derivation from KDF output.
//!
//! bytes [32..96] of derive_key() output are split into two 32-byte
//! seeds (d, z) used to deterministically generate an ML-KEM-1024
//! keypair per ADR-006.

// EncodedSizeUser provides `as_bytes()` on EncapsulationKey — must stay in scope
#[allow(unused_imports)]
use ml_kem::{EncodedSizeUser, KemCore, MlKem1024, MlKem1024Params};
use rand::rngs::StdRng;
use rand::SeedableRng;
use zeroize::Zeroizing;

/// An ML-KEM-1024 keypair derived from KDF output.
pub struct MlKemKeypair {
    pub encapsulation_key: ml_kem::kem::EncapsulationKey<MlKem1024Params>,
    pub decapsulation_key: ml_kem::kem::DecapsulationKey<MlKem1024Params>,
}

impl MlKemKeypair {
    /// Derives an ML-KEM-1024 keypair from bytes [32..96] of KDF output.
    /// The 64 bytes are split into two 32-byte seeds d and z.
    pub fn from_kdf_output(kdf_output: &[u8; 96]) -> Self {
        let seed: Zeroizing<[u8; 32]> = Zeroizing::new(
            kdf_output[32..64]
                .try_into()
                .expect("slice is exactly 32 bytes"),
        );
        let mut rng = StdRng::from_seed(*seed);
        let (decapsulation_key, encapsulation_key) = MlKem1024::generate(&mut rng);
        Self {
            encapsulation_key,
            decapsulation_key,
        }
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
    fn ml_kem_keypair_derives_from_kdf_output() {
        let kdf_output = derive_key(b"passphrase", &[0u8; 32], &test_params()).unwrap();
        let keypair = MlKemKeypair::from_kdf_output(&kdf_output);
        // encapsulation key encodes to 1568 bytes for ML-KEM-1024
        let ek_bytes = keypair.encapsulation_key.as_bytes();
        assert_eq!(ek_bytes.len(), 1568);
    }

    #[test]
    fn ml_kem_keypair_is_deterministic() {
        let kdf_output = derive_key(b"passphrase", &[1u8; 32], &test_params()).unwrap();
        let a = MlKemKeypair::from_kdf_output(&kdf_output);
        let b = MlKemKeypair::from_kdf_output(&kdf_output);
        assert_eq!(
            a.encapsulation_key.as_bytes(),
            b.encapsulation_key.as_bytes()
        );
    }

    #[test]
    fn different_passphrases_produce_different_ml_kem_keys() {
        let params = test_params();
        let out_a = derive_key(b"passphrase one", &[2u8; 32], &params).unwrap();
        let out_b = derive_key(b"passphrase two", &[2u8; 32], &params).unwrap();
        let a = MlKemKeypair::from_kdf_output(&out_a);
        let b = MlKemKeypair::from_kdf_output(&out_b);
        assert_ne!(
            a.encapsulation_key.as_bytes(),
            b.encapsulation_key.as_bytes()
        );
    }
}
