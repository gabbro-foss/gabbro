//! Vault file I/O — writing and reading `.gabbro` files on disk.
//!
//! These functions are thin wrappers around `SealedVault::to_bytes()`
//! and `SealedVault::from_bytes()`. All crypto happens in `vault_crypto.rs`;
//! all serialization happens in `file_format.rs`. This module only touches
//! the filesystem.

use std::fs;
use std::path::Path;

use crate::vault::file_format::SealedVault;

/// Write a sealed vault to a `.gabbro` file at the given path.
///
/// Creates or overwrites the file. The caller is responsible for
/// choosing a safe path — this function does not enforce the `.gabbro`
/// extension.
pub fn write_vault(sealed: &SealedVault, path: &Path) -> Result<(), String> {
    let bytes = sealed.to_bytes();
    fs::write(path, bytes).map_err(|e| format!("Failed to write vault: {e}"))
}

/// Read a `.gabbro` file from disk and deserialize it into a `SealedVault`.
///
/// Returns `Err` if the file cannot be read or if the bytes are not a
/// valid Gabbro vault.
pub fn read_vault(path: &Path) -> Result<SealedVault, String> {
    let bytes = fs::read(path).map_err(|e| format!("Failed to read vault: {e}"))?;
    SealedVault::from_bytes(&bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::vault_crypto::{seal_vault, open_vault};
    use std::env::temp_dir;

    fn temp_vault_path() -> std::path::PathBuf {
        let mut path = temp_dir();
        path.push("gabbro_test.gabbro");
        path
    }

    #[test]
    fn write_and_read_roundtrip() {
        let path = temp_vault_path();
        let passphrase = b"correct horst battery staple";
        let plaintext = b"vault io roundtrip test";

        let sealed = seal_vault(passphrase, plaintext).unwrap();
        write_vault(&sealed, &path).unwrap();
        let recovered_sealed = read_vault(&path).unwrap();
        let recovered_plaintext = open_vault(passphrase, &recovered_sealed).unwrap();

        assert_eq!(recovered_plaintext, plaintext);

        // Clean up — don't leave test files on disk
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn read_nonexistent_file_returns_error() {
        let path = Path::new("/tmp/does_not_exist_gabbro_test.gabbro");
        assert!(read_vault(path).is_err());
    }

    #[test]
    fn read_invalid_bytes_returns_error() {
        let path = temp_vault_path();
        fs::write(&path, b"this is not a gabbro vault").unwrap();
        let result = read_vault(&path);
        let _ = std::fs::remove_file(&path);
        assert!(result.is_err());
    }

}