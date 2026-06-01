//! ML-KEM-1024 keypair derivation from KDF output.
//!
//! Two derivation paths exist, dispatched by vault file version:
//!
//! - **FIPS (VERSION 6+)** — [`MlKemKeypair::from_kdf_output_fips`] feeds
//!   `d = kdf[32..64]` and `z = kdf[64..96]` directly into FIPS 203 §7.1
//!   `ML-KEM.KeyGen(d, z)`. Uses all 64 bytes; no PRNG indirection.
//! - **Legacy (VERSION 2–5)** — [`MlKemKeypair::from_kdf_output_legacy`] seeds
//!   `StdRng` (ChaCha12) with `kdf[32..64]` and samples `(d, z)` from it,
//!   ignoring `kdf[64..96]`. Retained only to read vaults sealed by older
//!   builds; not FIPS-203-conformant (see AI_SECURITY_AUDIT F-02).

// EncodedSizeUser provides `as_bytes()` on EncapsulationKey — must stay in scope
#[allow(unused_imports)]
use ml_kem::{EncodedSizeUser, KemCore, MlKem1024, MlKem1024Params, B32};
use rand::rngs::StdRng;
use rand::SeedableRng;
use zeroize::Zeroizing;

/// An ML-KEM-1024 keypair derived from KDF output.
pub struct MlKemKeypair {
    pub encapsulation_key: ml_kem::kem::EncapsulationKey<MlKem1024Params>,
    pub decapsulation_key: ml_kem::kem::DecapsulationKey<MlKem1024Params>,
}

impl MlKemKeypair {
    /// FIPS 203 §7.1 `ML-KEM.KeyGen(d, z)` (VERSION 6+).
    ///
    /// `d = kdf_output[32..64]`, `z = kdf_output[64..96]` are passed directly
    /// to the deterministic KeyGen — no `StdRng` indirection, and all 64 bytes
    /// of the ML-KEM portion are consumed.
    pub fn from_kdf_output_fips(kdf_output: &[u8; 96]) -> Self {
        let d_bytes: Zeroizing<[u8; 32]> = Zeroizing::new(
            kdf_output[32..64]
                .try_into()
                .expect("slice is exactly 32 bytes"),
        );
        let z_bytes: Zeroizing<[u8; 32]> = Zeroizing::new(
            kdf_output[64..96]
                .try_into()
                .expect("slice is exactly 32 bytes"),
        );
        let d = B32::try_from(&d_bytes[..]).expect("slice is exactly 32 bytes");
        let z = B32::try_from(&z_bytes[..]).expect("slice is exactly 32 bytes");
        let (decapsulation_key, encapsulation_key) = MlKem1024::generate_deterministic(&d, &z);
        Self {
            encapsulation_key,
            decapsulation_key,
        }
    }

    /// Legacy `StdRng`-seeded derivation (VERSION 2–5 vaults only).
    ///
    /// Seeds `StdRng` with `kdf_output[32..64]` and lets the KEM sample
    /// `(d, z)` from that stream. Bytes `[64..96]` are ignored. Kept solely so
    /// vaults written by older builds remain readable; do not use for new vaults.
    pub fn from_kdf_output_legacy(kdf_output: &[u8; 96]) -> Self {
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
    use ml_kem::kem::{Decapsulate, Encapsulate};
    use rand::rngs::OsRng;

    fn test_params() -> Argon2idParams {
        Argon2idParams {
            m_cost: 4096,
            t_cost: 1,
            p_cost: 1,
        }
    }

    // ── FIPS path (VERSION 6) ────────────────────────────────────────────────

    #[test]
    fn fips_keypair_derives_with_correct_ek_size() {
        let kdf_output = derive_key(b"passphrase", &[0u8; 32], &test_params()).unwrap();
        let keypair = MlKemKeypair::from_kdf_output_fips(&kdf_output);
        // encapsulation key encodes to 1568 bytes for ML-KEM-1024
        assert_eq!(keypair.encapsulation_key.as_bytes().len(), 1568);
    }

    #[test]
    fn fips_keypair_is_deterministic() {
        let kdf_output = derive_key(b"passphrase", &[1u8; 32], &test_params()).unwrap();
        let a = MlKemKeypair::from_kdf_output_fips(&kdf_output);
        let b = MlKemKeypair::from_kdf_output_fips(&kdf_output);
        assert_eq!(
            a.encapsulation_key.as_bytes(),
            b.encapsulation_key.as_bytes()
        );
    }

    #[test]
    fn fips_different_passphrases_produce_different_keys() {
        let params = test_params();
        let out_a = derive_key(b"passphrase one", &[2u8; 32], &params).unwrap();
        let out_b = derive_key(b"passphrase two", &[2u8; 32], &params).unwrap();
        let a = MlKemKeypair::from_kdf_output_fips(&out_a);
        let b = MlKemKeypair::from_kdf_output_fips(&out_b);
        assert_ne!(
            a.encapsulation_key.as_bytes(),
            b.encapsulation_key.as_bytes()
        );
    }

    /// FIPS 203 KeyGen consumes `z = kdf[64..96]`; the legacy path ignored those
    /// bytes. Per the standard, `z` is the implicit-rejection secret carried in
    /// the *decapsulation* key only — it does NOT affect the public encapsulation
    /// key. So for two inputs identical in `[0..64]` but differing in `[64..96]`,
    /// FIPS yields the same `ek` but a different `dk` (z is consumed), whereas the
    /// legacy path yields an identical `dk` (those bytes are ignored). This pins
    /// the "dead bytes" fix (audit F-02 / F-07).
    #[test]
    fn fips_uses_z_bytes_64_to_96() {
        let mut a = [7u8; 96];
        let mut b = [7u8; 96];
        a[64..96].fill(0x11);
        b[64..96].fill(0x22);

        let fips_a = MlKemKeypair::from_kdf_output_fips(&a);
        let fips_b = MlKemKeypair::from_kdf_output_fips(&b);
        assert_eq!(
            fips_a.encapsulation_key.as_bytes(),
            fips_b.encapsulation_key.as_bytes(),
            "z (FO implicit-rejection secret) must not affect the public ek"
        );
        assert_ne!(
            fips_a.decapsulation_key.as_bytes(),
            fips_b.decapsulation_key.as_bytes(),
            "FIPS dk must depend on z (bytes 64..96)"
        );

        let legacy_a = MlKemKeypair::from_kdf_output_legacy(&a);
        let legacy_b = MlKemKeypair::from_kdf_output_legacy(&b);
        assert_eq!(
            legacy_a.decapsulation_key.as_bytes(),
            legacy_b.decapsulation_key.as_bytes(),
            "legacy path ignores bytes 64..96 (documents the bug being fixed)"
        );
    }

    /// FIPS and legacy derive DIFFERENT keypairs from the same input — this is
    /// why a VERSION 6 vault cannot be opened with the legacy keygen and why
    /// keygen must be dispatched on the vault version.
    #[test]
    fn fips_differs_from_legacy() {
        let kdf_output = derive_key(b"passphrase", &[3u8; 32], &test_params()).unwrap();
        let fips = MlKemKeypair::from_kdf_output_fips(&kdf_output);
        let legacy = MlKemKeypair::from_kdf_output_legacy(&kdf_output);
        assert_ne!(
            fips.encapsulation_key.as_bytes(),
            legacy.encapsulation_key.as_bytes()
        );
    }

    /// Functional round-trip: a secret encapsulated to the FIPS encapsulation key
    /// decapsulates to the same shared secret with the matching decapsulation key.
    #[test]
    fn fips_encapsulate_decapsulate_roundtrip() {
        let kdf_output = derive_key(b"passphrase", &[4u8; 32], &test_params()).unwrap();
        let keypair = MlKemKeypair::from_kdf_output_fips(&kdf_output);
        let (ciphertext, shared_a) = keypair
            .encapsulation_key
            .encapsulate(&mut OsRng)
            .expect("encapsulation succeeds");
        let shared_b = keypair
            .decapsulation_key
            .decapsulate(&ciphertext)
            .expect("decapsulation succeeds");
        assert_eq!(shared_a, shared_b);
    }

    // ── Legacy path (VERSION 2–5) ────────────────────────────────────────────

    #[test]
    fn legacy_keypair_is_deterministic() {
        let kdf_output = derive_key(b"passphrase", &[5u8; 32], &test_params()).unwrap();
        let a = MlKemKeypair::from_kdf_output_legacy(&kdf_output);
        let b = MlKemKeypair::from_kdf_output_legacy(&kdf_output);
        assert_eq!(
            a.encapsulation_key.as_bytes(),
            b.encapsulation_key.as_bytes()
        );
    }
}
