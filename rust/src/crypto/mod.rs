//! Cryptographic primitives for vault encryption and decryption.
//!
//! This module is internal — nothing here is exposed to Flutter directly.
//! Flutter calls functions in `api/` which orchestrate these primitives.

pub mod kdf;
pub mod keypair;
pub mod ml_kem;