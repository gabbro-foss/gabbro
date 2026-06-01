//! Vault file I/O — writing and reading `.gabbro` files on disk.
//!
//! These functions are thin wrappers around `SealedVault::to_bytes()`
//! and `SealedVault::from_bytes()`. All crypto happens in `vault_crypto.rs`;
//! all serialization happens in `file_format.rs`. This module only touches
//! the filesystem.

use std::fs;
use std::path::{Path, PathBuf};

use crate::vault::file_format::{SealedVault, YubiKeyRecord};

/// Reject a path that is a symlink.
fn check_not_symlink(path: &Path) -> Result<(), String> {
    if let Ok(m) = fs::symlink_metadata(path) {
        if m.file_type().is_symlink() {
            return Err(format!(
                "Vault path is a symlink — refusing for security: {}",
                path.display()
            ));
        }
    }
    Ok(())
}

/// Atomically write `data` to `path`.
///
/// On Unix: creates the file with mode 0600, writes to a sibling `.tmp` file,
/// fsyncs, then renames atomically so the destination is never half-written.
/// On non-Unix: falls back to a plain `fs::write`.
pub(crate) fn atomic_write_0600(path: &Path, data: &[u8]) -> Result<(), String> {
    #[cfg(unix)]
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;

        let mut tmp_name = path.as_os_str().to_owned();
        tmp_name.push(".tmp");
        let tmp = PathBuf::from(tmp_name);

        let mut f = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(&tmp)
            .map_err(|e| format!("Failed to create temp file: {e}"))?;
        f.write_all(data)
            .map_err(|e| format!("Failed to write data: {e}"))?;
        f.sync_all()
            .map_err(|e| format!("Failed to sync file: {e}"))?;
        drop(f);
        fs::rename(&tmp, path).map_err(|e| format!("Failed to rename temp file: {e}"))
    }
    #[cfg(not(unix))]
    {
        fs::write(path, data).map_err(|e| format!("Failed to write: {e}"))
    }
}

/// Write a sealed vault to a `.gabbro` file at the given path.
///
/// Refuses symlinks. Writes atomically with mode 0600 on Unix.
pub fn write_vault(sealed: &SealedVault, path: &Path) -> Result<(), String> {
    check_not_symlink(path)?;
    let bytes = sealed.to_bytes();
    atomic_write_0600(path, &bytes)
}

/// Read a `.gabbro` file from disk and deserialize it into a `SealedVault`.
///
/// Refuses symlinks. Returns `Err` if the file cannot be read or if the bytes
/// are not a valid Gabbro vault.
pub fn read_vault(path: &Path) -> Result<SealedVault, String> {
    check_not_symlink(path)?;
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

    fn temp_vault_path() -> PathBuf {
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

        let _ = fs::remove_file(&path);
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

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn read_vault_header_alias_none_when_not_set() {
        use crate::crypto::vault_crypto::seal_vault;

        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_header_noalias_test.gabbro");
            p
        };
        let passphrase = b"no alias test";
        let plaintext = b"no alias body";

        let sealed = seal_vault(passphrase, plaintext).unwrap();
        write_vault(&sealed, &path).unwrap();

        let header = read_vault_header(&path).unwrap();
        assert_eq!(header.alias, None);

        let _ = fs::remove_file(&path);
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
        let _ = fs::remove_file(&path);
        assert!(result.is_err());
    }

    // F-08: vault files must be written with mode 0600 on Unix
    #[cfg(unix)]
    #[test]
    fn write_vault_creates_0600_file() {
        use std::os::unix::fs::PermissionsExt;

        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_perms_test.gabbro");
            p
        };
        let passphrase = b"perms test passphrase";
        let plaintext = b"perms test body";

        let sealed = seal_vault(passphrase, plaintext).unwrap();
        write_vault(&sealed, &path).unwrap();

        let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        let _ = fs::remove_file(&path);
        assert_eq!(mode, 0o600, "expected 0600, got {:#o}", mode);
    }

    // F-09: vault write must reject symlinks
    #[cfg(unix)]
    #[test]
    fn write_vault_rejects_symlink() {
        use std::os::unix::fs::symlink;

        let dir = temp_dir();
        let real = dir.join("gabbro_io_symlink_real.gabbro");
        let link = dir.join("gabbro_io_symlink_link.gabbro");
        let _ = fs::remove_file(&real);
        let _ = fs::remove_file(&link);
        fs::write(&real, b"placeholder").unwrap();
        symlink(&real, &link).unwrap();

        let sealed = seal_vault(b"pw", b"body").unwrap();
        let err = write_vault(&sealed, &link).unwrap_err();

        let _ = fs::remove_file(&real);
        let _ = fs::remove_file(&link);
        assert!(
            err.contains("symlink"),
            "expected symlink error, got: {err}"
        );
    }

    // F-09: vault read must reject symlinks
    #[cfg(unix)]
    #[test]
    fn read_vault_rejects_symlink() {
        use std::os::unix::fs::symlink;

        let dir = temp_dir();
        let real = dir.join("gabbro_io_rd_symlink_real.gabbro");
        let link = dir.join("gabbro_io_rd_symlink_link.gabbro");
        let _ = fs::remove_file(&real);
        let _ = fs::remove_file(&link);

        let sealed = seal_vault(b"pw", b"body").unwrap();
        let bytes = sealed.to_bytes();
        fs::write(&real, &bytes).unwrap();
        symlink(&real, &link).unwrap();

        let err = read_vault(&link).unwrap_err();

        let _ = fs::remove_file(&real);
        let _ = fs::remove_file(&link);
        assert!(
            err.contains("symlink"),
            "expected symlink error, got: {err}"
        );
    }
}
