//! Argon2id key derivation function and parameters.

/// Parameters for the Argon2id KDF.
///
/// These are stored in the vault file header so that a vault can
/// always be decrypted using the parameters it was created with,
/// even if the defaults change in a future version.

use argon2::{Argon2, Algorithm, Version, Params};

#[derive(Debug, Clone, PartialEq)]
pub struct Argon2idParams {
    /// Memory cost in kibibytes.
    pub m_cost: u32,
    /// Number of iterations.
    pub t_cost: u32,
    /// Parallelism (number of threads).
    pub p_cost: u32,
}

impl Argon2idParams {
    /// Returns the recommended default parameters per ADR-006.
    pub fn default() -> Self {
        Self {
            m_cost: 65536,
            t_cost: 25,
            p_cost: 4,
        }
    }
}

/// Derives 96 bytes of key material from a passphrase and salt.
///
/// The output is split by the caller:
///   bytes [0..32]  → X25519 private key
///   bytes [32..96] → ML-KEM-1024 private key seed
///
/// The salt must be exactly 32 bytes. Use a cryptographically random
/// salt generated fresh for each new vault.
pub fn derive_key(
    passphrase: &[u8],
    salt: &[u8; 32],
    params: &Argon2idParams,
) -> Result<[u8; 96], String> {
    let argon2_params = Params::new(
        params.m_cost,
        params.t_cost,
        params.p_cost,
        Some(96),
    ).map_err(|e| format!("invalid Argon2id params: {e}"))?;

    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, argon2_params);

    let mut output = [0u8; 96];
    argon2
        .hash_password_into(passphrase, salt, &mut output)
        .map_err(|e| format!("Argon2id derivation failed: {e}"))?;

    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_params_are_correct() {
        let p = Argon2idParams::default();
        assert_eq!(p.m_cost, 65536);
        assert_eq!(p.t_cost, 25);
        assert_eq!(p.p_cost, 4);
    }

    #[test]
    fn params_can_be_cloned() {
        let p = Argon2idParams::default();
        let q = p.clone();
        assert_eq!(p, q);
    }

    #[test]
    fn derive_key_returns_96_bytes() {
        let salt = [0u8; 32];
        let params = Argon2idParams {
            m_cost: 4096, // low cost for tests
            t_cost: 1,
            p_cost: 1,
        };
        let result = derive_key(b"test passphrase", &salt, &params);
        assert!(result.is_ok(), "derivation failed: {:?}", result);
        let key = result.unwrap();
        assert_eq!(key.len(), 96);
    }

    #[test]
    fn derive_key_is_deterministic() {
        let salt = [1u8; 32];
        let params = Argon2idParams { m_cost: 4096, t_cost: 1, p_cost: 1 };
        let a = derive_key(b"passphrase", &salt, &params).unwrap();
        let b = derive_key(b"passphrase", &salt, &params).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn different_passphrases_produce_different_keys() {
        let salt = [2u8; 32];
        let params = Argon2idParams { m_cost: 4096, t_cost: 1, p_cost: 1 };
        let a = derive_key(b"passphrase one", &salt, &params).unwrap();
        let b = derive_key(b"passphrase two", &salt, &params).unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn different_salts_produce_different_keys() {
        let params = Argon2idParams { m_cost: 4096, t_cost: 1, p_cost: 1 };
        let a = derive_key(b"passphrase", &[3u8; 32], &params).unwrap();
        let b = derive_key(b"passphrase", &[4u8; 32], &params).unwrap();
        assert_ne!(a, b);
    }

}