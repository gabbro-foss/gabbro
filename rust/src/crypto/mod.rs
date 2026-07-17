//! Cryptographic primitives for vault encryption and decryption.
//!
//! This module is internal — nothing here is exposed to Flutter directly.
//! Flutter calls functions in `api/` which orchestrate these primitives.

pub mod aes_gcm;
pub mod hkdf;
pub mod kdf;
pub mod vault_crypto;
