//! Vault file I/O — writing and reading `.gabbro` files on disk.
//!
//! These functions are thin wrappers around `SealedVault::to_bytes()`
//! and `SealedVault::from_bytes()`. All crypto happens in `vault_crypto.rs`;
//! all serialization happens in `file_format.rs`. This module only touches
//! the filesystem.

use std::fs;
use std::path::Path;

use crate::vault::file_format::{SealedVault, YubiKeyRecord};

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

/// Lightweight vault header: alias and YubiKey records only, no body decryption.
pub struct VaultHeader {
    pub alias: Option<String>,
    pub yubikey_records: Vec<YubiKeyRecord>,
}

/// Read the vault header at `path` without decrypting the body.
///
/// Returns alias and YubiKey records. Safe to call before passphrase entry.
pub fn read_vault_header(path: &Path) -> Result<VaultHeader, String> {
    let sealed = read_vault(path)?;
    Ok(VaultHeader {
        alias: sealed.alias,
        yubikey_records: sealed.yubikey_records,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::vault_crypto::{open_vault, seal_vault};
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
    fn read_vault_header_returns_alias_and_yubikey_records() {
        use crate::crypto::vault_crypto::seal_vault;

        let path = temp_vault_path();
        let passphrase = b"header test passphrase";
        let plaintext = b"header test body";

        let mut sealed = seal_vault(passphrase, plaintext).unwrap();
        sealed.alias = Some("Personal".to_string());
        write_vault(&sealed, &path).unwrap();

        let header = read_vault_header(&path).unwrap();
        assert_eq!(header.alias, Some("Personal".to_string()));
        assert!(header.yubikey_records.is_empty());

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn read_vault_header_alias_none_when_not_set() {
        use crate::crypto::vault_crypto::seal_vault;

        let path = {
            let mut p = std::env::temp_dir();
            p.push("gabbro_io_header_noalias_test.gabbro");
            p
        };
        let passphrase = b"no alias test";
        let plaintext = b"no alias body";

        let sealed = seal_vault(passphrase, plaintext).unwrap();
        write_vault(&sealed, &path).unwrap();

        let header = read_vault_header(&path).unwrap();
        assert_eq!(header.alias, None);

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
