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

        // O_NOFOLLOW so a pre-planted symlink at `<path>.tmp` fails closed
        // instead of redirecting the write to an attacker-chosen target (S-04).
        // A stale *regular* temp is still overwritten (create + truncate).
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
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

/// The `.bak` sibling path for a vault path.
fn bak_path(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_owned();
    name.push(".bak");
    PathBuf::from(name)
}

/// R-03: before overwriting an existing vault, keep the previous sealed bytes
/// as a sibling `.bak`. Crash/corruption insurance for the save path — not a
/// backup (same disk) and not undo (advances on every save).
fn rotate_backup(path: &Path) -> Result<(), String> {
    if fs::symlink_metadata(path).is_err() {
        return Ok(()); // first save: nothing to rotate
    }
    let bak = bak_path(path);
    // Fail-closed, and say so: every rotation error reaches the user prefixed
    // with what failed (the safety copy), not just a low-level reason.
    check_not_symlink(&bak).map_err(|e| format!("Vault backup rotation failed: {e}"))?;
    let previous = fs::read(path)
        .map_err(|e| format!("Vault backup rotation failed — could not read the vault: {e}"))?;
    atomic_write_0600(&bak, &previous).map_err(|e| format!("Vault backup rotation failed: {e}"))
}

/// R-03: make the `.bak` identical to the current on-disk vault.
///
/// Used after credential-changing operations (passphrase change, YubiKey
/// add/remove): a rotated `.bak` would hold the *old* credential set, which
/// the user may no longer remember or hold — so those operations forfeit the
/// one-save rollback window and refresh the safety copy to match instead.
pub(crate) fn sync_backup_to_current(path: &Path) -> Result<(), String> {
    let bak = bak_path(path);
    check_not_symlink(&bak).map_err(|e| format!("Vault backup refresh failed: {e}"))?;
    let current = fs::read(path)
        .map_err(|e| format!("Vault backup refresh failed — could not read the vault: {e}"))?;
    atomic_write_0600(&bak, &current).map_err(|e| format!("Vault backup refresh failed: {e}"))
}

/// R-03: refresh the `.bak` after a credential change that already persisted.
///
/// If the refresh fails, the stale `.bak` is removed — it holds the *old*
/// credential set, which the user may no longer remember or hold, and a
/// misleading backup is worse than none. The error states explicitly that the
/// credential change itself succeeded, so the user is not tempted to retry it.
pub(crate) fn refresh_backup_after_credential_change(path: &Path) -> Result<(), String> {
    if let Err(e) = sync_backup_to_current(path) {
        let _ = remove_backup(path);
        return Err(format!(
            "The change succeeded, but the vault safety copy could not be refreshed \
             and was removed instead: {e}"
        ));
    }
    Ok(())
}

/// R-03 P1: after the main vault is written, confirm the bytes read back as a
/// valid vault, then advance the `.bak` to match — so the safety copy always
/// equals the last *verified* save, never one save behind (the defect that
/// lost a just-made edit when a user restored after corruption).
///
/// If the just-written bytes do not parse, the `.bak` is left at the previous
/// good save and a loud error is returned: this is the 2026-06-08 brick class
/// firing at the moment of the bad save instead of silently propagating into
/// the safety copy.
fn verify_and_sync_backup(path: &Path) -> Result<(), String> {
    let written = fs::read(path).map_err(|e| {
        format!("Vault save verification failed — could not re-read the vault: {e}")
    })?;
    SealedVault::from_bytes(&written).map_err(|e| {
        format!(
            "The vault was written but did not read back as a valid vault; \
             the safety copy was kept at the last good save: {e}"
        )
    })?;
    sync_backup_to_current(path)
}

/// Write a sealed vault to a `.gabbro` file at the given path.
///
/// Refuses symlinks. Rotates the previous save to `.bak` as mid-write crash
/// insurance (fail-closed: a rotation error aborts the save, leaving the
/// on-disk vault untouched), writes atomically with mode 0600 on Unix, then
/// verifies the just-written bytes parse and syncs the `.bak` to them — so the
/// safety copy always equals the last verified save (R-03 P1). A write that
/// does not read back as a valid vault leaves the `.bak` at the previous good
/// save and returns an error.
pub fn write_vault(sealed: &SealedVault, path: &Path) -> Result<(), String> {
    check_not_symlink(path)?;
    rotate_backup(path)?;
    let bytes = sealed.to_bytes();
    atomic_write_0600(path, &bytes)?;
    verify_and_sync_backup(path)
}

/// R-03: delete the `.bak` safety copy, if any. Absence is not an error.
///
/// Called by vault deletion so no copy of a deleted vault survives.
pub(crate) fn remove_backup(path: &Path) -> Result<(), String> {
    match fs::remove_file(bak_path(path)) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("Failed to delete the vault backup: {e}")),
    }
}

/// R-03: does a `.bak` safety copy exist for this vault path?
///
/// Reports `false` for a symlinked `.bak` — restore would refuse it anyway,
/// so the unlock screen must not offer it.
pub fn backup_exists(path: &Path) -> bool {
    matches!(fs::symlink_metadata(bak_path(path)), Ok(m) if m.is_file())
}

/// R-03 P3: is the `.bak` a *usable* vault — present, not a symlink, and
/// parseable as a Gabbro vault?
///
/// Drives whether the unlock screen may offer a restore. Mere existence is not
/// enough: a `.bak` that has itself rotted to garbage must never be advertised
/// as "a safety copy is available", or the offer lies and a confirmed restore
/// is then refused (hardware-found 2026-06-11). Parsing does no KDF work, so
/// this is cheap to call before passphrase entry.
pub fn backup_usable(path: &Path) -> bool {
    let bak = bak_path(path);
    if check_not_symlink(&bak).is_err() {
        return false;
    }
    match fs::read(&bak) {
        Ok(bytes) => SealedVault::from_bytes(&bytes).is_ok(),
        Err(_) => false,
    }
}

/// R-03: replace the main vault file with the `.bak` safety copy.
///
/// Only called from the unlock screen's explicit restore flow, after the user
/// has confirmed. Refuses symlinks on both paths. The restored vault still
/// requires full credentials to open — restoring grants no access.
pub fn restore_vault_backup(path: &Path) -> Result<(), String> {
    check_not_symlink(path)?;
    let bak = bak_path(path);
    check_not_symlink(&bak)?;
    let bytes = fs::read(&bak).map_err(|e| format!("No vault backup to restore: {e}"))?;
    // Never replace the main file with bytes that are not themselves a vault:
    // a corrupt .bak restored over a corrupt main would destroy the evidence
    // of both without helping the user.
    SealedVault::from_bytes(&bytes)
        .map_err(|e| format!("The vault backup is not usable — restore refused: {e}"))?;
    atomic_write_0600(path, &bytes)
}

/// R-03: replace the vault file at `path` with an external backup file the user
/// picked (their own off-device 3-2-1 copy).
///
/// Validates that `source` parses as a vault before overwriting — never replace
/// an unreadable vault with another unreadable file. Refuses symlinks on both
/// paths. The restored vault still requires full credentials to open, so this
/// grants no access by itself.
pub fn restore_vault_from_file(path: &Path, source: &Path) -> Result<(), String> {
    check_not_symlink(path)?;
    check_not_symlink(source)?;
    let bytes = fs::read(source).map_err(|e| format!("Could not read the backup file: {e}"))?;
    SealedVault::from_bytes(&bytes)
        .map_err(|e| format!("That file is not a usable Gabbro vault — restore refused: {e}"))?;
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

/// Whether the vault file at `path` predates the readable floor (see
/// [`crate::vault::file_format::is_format_too_old`]).
///
/// Lets the unlock screen tell "intact but too old to open" apart from "corrupt",
/// so an old vault is explained rather than reported as damaged with an offer to
/// delete it. Reads the first bytes only; decrypts nothing.
pub fn vault_format_too_old(path: &Path) -> Result<bool, String> {
    check_not_symlink(path)?;
    let bytes = fs::read(path).map_err(|e| format!("Failed to read vault: {e}"))?;
    crate::vault::file_format::is_format_too_old(&bytes)
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

        let sealed = seal_vault(passphrase, plaintext, None).unwrap();
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

        let mut sealed = seal_vault(passphrase, plaintext, None).unwrap();
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

        let sealed = seal_vault(passphrase, plaintext, None).unwrap();
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

    // R-03 (discovered, maintainer-approved): if the post-credential-change refresh
    // fails, the stale .bak (old credentials) must be removed and the error
    // must say the change itself succeeded
    #[cfg(unix)]
    #[test]
    fn refresh_failure_removes_stale_bak_and_says_change_succeeded() {
        use std::os::unix::fs::symlink;

        let dir = temp_dir();
        let path = dir.join("gabbro_io_refresh_fail_test.gabbro");
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let target = dir.join("gabbro_io_refresh_fail_target");
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        let _ = fs::remove_file(&target);

        fs::write(&path, b"post-change vault bytes").unwrap();
        fs::write(&target, b"stale").unwrap();
        symlink(&target, &bak).unwrap(); // forces the refresh to fail

        let result = refresh_backup_after_credential_change(&path);
        let bak_gone = fs::symlink_metadata(&bak).is_err();
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        let _ = fs::remove_file(&target);

        let err = result.expect_err("a failed refresh must surface an error");
        assert!(
            err.to_lowercase().contains("succeeded"),
            "the error must say the credential change itself succeeded: {err}"
        );
        assert!(
            bak_gone,
            "the stale .bak must be removed — old credentials are worse than no backup"
        );
    }

    // R-03 P1: after a second save the .bak equals the CURRENT save (synced),
    // not the previous one — so a restore returns the user's latest state.
    #[test]
    fn second_write_syncs_bak_to_current_save() {
        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_bak_rotate_test.gabbro");
            p
        };
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        let sealed_a = seal_vault(b"pw-a", b"body version A", None).unwrap();
        write_vault(&sealed_a, &path).unwrap();

        let sealed_b = seal_vault(b"pw-b", b"body version B", None).unwrap();
        write_vault(&sealed_b, &path).unwrap();
        let bytes_b = fs::read(&path).unwrap();

        let bak_bytes = fs::read(&bak);
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        assert_eq!(
            bak_bytes.expect("second write must leave a .bak"),
            bytes_b,
            ".bak must hold the current save's exact bytes (synced, not trailing)"
        );
    }

    // R-03 P1: the .bak is a usable vault, openable with the CURRENT save's
    // credentials (the safety copy mirrors the last verified save).
    #[test]
    fn bak_opens_as_valid_vault_with_current_credentials() {
        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_bak_opens_test.gabbro");
            p
        };
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        let sealed_a = seal_vault(b"pw-old", b"older body", None).unwrap();
        write_vault(&sealed_a, &path).unwrap();
        let sealed_b = seal_vault(b"pw-new", b"newer body", None).unwrap();
        write_vault(&sealed_b, &path).unwrap();

        let recovered = read_vault(&bak).and_then(|s| open_vault(b"pw-new", &s));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        assert_eq!(
            recovered.expect(".bak must be readable and openable"),
            b"newer body",
            ".bak must decrypt to the current save's plaintext"
        );
    }

    // R-03 P1: the very first save creates a .bak equal to that save — the
    // safety copy mirrors the last verified save from the first one on.
    #[test]
    fn first_write_creates_bak_matching_save() {
        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_bak_first_write_test.gabbro");
            p
        };
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        let sealed = seal_vault(b"pw", b"first body", None).unwrap();
        write_vault(&sealed, &path).unwrap();

        let main_bytes = fs::read(&path).unwrap();
        let bak_bytes = fs::read(&bak);
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        assert_eq!(
            bak_bytes.expect("first write must create a .bak"),
            main_bytes,
            ".bak must equal the just-written vault from the first save"
        );
    }

    // R-03 P1: each save syncs the .bak to the current vault — after the third
    // save it holds the third save, not an older one.
    #[test]
    fn third_write_syncs_bak_to_current_save() {
        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_bak_replace_test.gabbro");
            p
        };
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        let sealed_a = seal_vault(b"pw-a", b"body A", None).unwrap();
        write_vault(&sealed_a, &path).unwrap();
        let sealed_b = seal_vault(b"pw-b", b"body B", None).unwrap();
        write_vault(&sealed_b, &path).unwrap();
        let sealed_c = seal_vault(b"pw-c", b"body C", None).unwrap();
        write_vault(&sealed_c, &path).unwrap();
        let bytes_c = fs::read(&path).unwrap();

        let bak_bytes = fs::read(&bak);
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        assert_eq!(
            bak_bytes.expect(".bak must exist after the third save"),
            bytes_c,
            ".bak must hold exactly the current (third) save, not an older one"
        );
    }

    // R-03 P1: if a save's bytes land on disk but do not parse, the .bak must
    // be left at the last good save and a loud error returned — the brick class
    // firing at the bad save, not silently propagating into the safety copy.
    #[test]
    fn unparseable_written_vault_keeps_bak_at_last_good_and_errors() {
        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_verify_fail_test.gabbro");
            p
        };
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        // Two good saves -> steady state: main == .bak == save B.
        let sealed_a = seal_vault(b"pw-a", b"body A", None).unwrap();
        write_vault(&sealed_a, &path).unwrap();
        let sealed_b = seal_vault(b"pw-b", b"body B", None).unwrap();
        write_vault(&sealed_b, &path).unwrap();
        let good_bak = fs::read(&bak).unwrap();

        // Simulate a save that wrote unparseable bytes to the main file.
        fs::write(&path, b"written but not a valid vault").unwrap();
        let result = verify_and_sync_backup(&path);
        let bak_after = fs::read(&bak).unwrap();
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        let err = result.expect_err("an unparseable written vault must error");
        assert!(
            err.to_lowercase().contains("safety copy"),
            "the error must say the safety copy was kept at the last good save: {err}"
        );
        assert_eq!(
            bak_after, good_bak,
            ".bak must remain at the last good save when the new bytes do not parse"
        );
    }

    // R-03: the .bak is as private as the vault itself
    #[cfg(unix)]
    #[test]
    fn bak_file_has_mode_0600() {
        use std::os::unix::fs::PermissionsExt;

        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_bak_perms_test.gabbro");
            p
        };
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        let sealed_a = seal_vault(b"pw-a", b"body A", None).unwrap();
        write_vault(&sealed_a, &path).unwrap();
        let sealed_b = seal_vault(b"pw-b", b"body B", None).unwrap();
        write_vault(&sealed_b, &path).unwrap();

        let mode = fs::metadata(&bak).unwrap().permissions().mode() & 0o777;
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        assert_eq!(mode, 0o600, "expected .bak mode 0600, got {:#o}", mode);
    }

    // R-03 + F-09 parity: a symlinked .bak path aborts the save fail-closed,
    // leaving the on-disk vault untouched
    #[cfg(unix)]
    #[test]
    fn symlinked_bak_aborts_save_leaving_vault_untouched() {
        use std::os::unix::fs::symlink;

        let dir = temp_dir();
        let path = dir.join("gabbro_io_bak_symlink_test.gabbro");
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let target = dir.join("gabbro_io_bak_symlink_target");
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        let _ = fs::remove_file(&target);

        let sealed_a = seal_vault(b"pw-a", b"body A", None).unwrap();
        write_vault(&sealed_a, &path).unwrap();
        let bytes_a = fs::read(&path).unwrap();

        // Drop the .bak the first save synced, so we can plant a symlink in its
        // place and prove the NEXT save aborts on it.
        let _ = fs::remove_file(&bak);
        fs::write(&target, b"attacker-chosen target").unwrap();
        symlink(&target, &bak).unwrap();

        let sealed_b = seal_vault(b"pw-b", b"body B", None).unwrap();
        let result = write_vault(&sealed_b, &path);
        let vault_after = fs::read(&path).unwrap();
        let target_after = fs::read(&target).unwrap();
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        let _ = fs::remove_file(&target);

        assert!(result.is_err(), "save through a symlinked .bak must fail");
        assert_eq!(
            vault_after, bytes_a,
            "failed save must leave the vault untouched"
        );
        assert_eq!(
            target_after, b"attacker-chosen target",
            "the symlink target must never be written through"
        );
    }

    // R-03: when rotation fails, the user-facing reason must say the backup
    // step failed (not a bare low-level message)
    #[cfg(unix)]
    #[test]
    fn rotation_failure_error_names_the_backup_step() {
        use std::os::unix::fs::symlink;

        let dir = temp_dir();
        let path = dir.join("gabbro_io_bak_errmsg_test.gabbro");
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let target = dir.join("gabbro_io_bak_errmsg_target");
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        let _ = fs::remove_file(&target);

        let sealed_a = seal_vault(b"pw-a", b"body A", None).unwrap();
        write_vault(&sealed_a, &path).unwrap();
        // Drop the synced .bak so the symlink can take its place for this probe.
        let _ = fs::remove_file(&bak);
        fs::write(&target, b"x").unwrap();
        symlink(&target, &bak).unwrap();

        let err = write_vault(&seal_vault(b"pw-b", b"body B", None).unwrap(), &path)
            .expect_err("symlinked .bak must fail the save");
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        let _ = fs::remove_file(&target);

        assert!(
            err.to_lowercase().contains("backup"),
            "error must name the backup step so the user knows what failed: {err}"
        );
    }

    // R-03: restore replaces the main vault with the .bak bytes
    #[test]
    fn restore_vault_backup_replaces_main_with_bak() {
        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_restore_test.gabbro");
            p
        };
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        let sealed_a = seal_vault(b"pw-a", b"good body", None).unwrap();
        write_vault(&sealed_a, &path).unwrap();
        let sealed_b = seal_vault(b"pw-b", b"later body", None).unwrap();
        write_vault(&sealed_b, &path).unwrap();
        let bytes_b = fs::read(&path).unwrap();
        // simulate corruption of the main file
        fs::write(&path, b"corrupt garbage").unwrap();

        let result = restore_vault_backup(&path);
        let main_after = fs::read(&path).unwrap();
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        result.expect("restore must succeed when a .bak exists");
        assert_eq!(
            main_after, bytes_b,
            "restore must replace the main vault with the .bak, which mirrors the last verified save"
        );
    }

    // R-03: restoring with no .bak present fails with a clear reason
    #[test]
    fn restore_vault_backup_errors_when_no_bak() {
        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_restore_nobak_test.gabbro");
            p
        };
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        let sealed = seal_vault(b"pw", b"only body", None).unwrap();
        write_vault(&sealed, &path).unwrap();
        // The save synced a .bak (R-03 P1); remove it to test the genuine
        // no-backup case.
        let _ = fs::remove_file(&bak);

        let err = restore_vault_backup(&path);
        let _ = fs::remove_file(&path);
        let err = err.expect_err("restore must fail when no .bak exists");
        assert!(
            err.to_lowercase().contains("backup"),
            "error must say there is no backup: {err}"
        );
    }

    // R-03 (discovered): never restore a .bak that does not parse as a vault —
    // replacing one corrupt file with another would destroy the evidence too
    #[test]
    fn restore_vault_backup_refuses_unparseable_bak() {
        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_restore_badbak_test.gabbro");
            p
        };
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        fs::write(&path, b"corrupt main").unwrap();
        fs::write(&bak, b"corrupt backup too").unwrap();

        let result = restore_vault_backup(&path);
        let main_after = fs::read(&path).unwrap();
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        assert!(result.is_err(), "restoring an unparseable .bak must fail");
        assert_eq!(
            main_after, b"corrupt main",
            "a refused restore must leave the main file untouched"
        );
    }

    // R-03: backup_exists drives whether the unlock screen offers a restore
    #[test]
    fn backup_exists_reports_presence() {
        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_bak_exists_test.gabbro");
            p
        };
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        let sealed_a = seal_vault(b"pw-a", b"body A", None).unwrap();
        write_vault(&sealed_a, &path).unwrap();
        let after_first = backup_exists(&path);

        let sealed_b = seal_vault(b"pw-b", b"body B", None).unwrap();
        write_vault(&sealed_b, &path).unwrap();
        let after_second = backup_exists(&path);

        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        assert!(after_first, ".bak present from the first save (synced)");
        assert!(after_second, ".bak still present after the second save");
    }

    // R-03 P3: backup_usable is true only when the .bak parses as a vault — a
    // garbage .bak must report false so the unlock screen cannot lie about it.
    #[test]
    fn backup_usable_true_only_for_parseable_bak() {
        let path = {
            let mut p = temp_dir();
            p.push("gabbro_io_bak_usable_test.gabbro");
            p
        };
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);

        assert!(!backup_usable(&path), "an absent .bak is not usable");

        let sealed = seal_vault(b"pw", b"body", None).unwrap();
        write_vault(&sealed, &path).unwrap(); // syncs a valid .bak
        assert!(backup_usable(&path), "a valid .bak must be usable");

        fs::write(&bak, b"not a vault").unwrap();
        let usable_after_garbage = backup_usable(&path);
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&bak);
        assert!(
            !usable_after_garbage,
            "a garbage .bak must report not usable"
        );
    }

    // R-03: restore_vault_from_file replaces a corrupt vault with a valid
    // external backup file the user picked, and the result is openable.
    #[test]
    fn restore_vault_from_file_replaces_corrupt_with_valid_source() {
        let dir = temp_dir();
        let path = dir.join("gabbro_io_restore_from_file_test.gabbro");
        let bak = PathBuf::from(format!("{}.bak", path.display()));
        let source = dir.join("gabbro_io_restore_from_file_source.gabbro");
        let source_bak = PathBuf::from(format!("{}.bak", source.display()));
        for p in [&path, &bak, &source, &source_bak] {
            let _ = fs::remove_file(p);
        }

        let sealed = seal_vault(b"backup pw", b"backup body", None).unwrap();
        write_vault(&sealed, &source).unwrap(); // a real backup vault
        let source_bytes = fs::read(&source).unwrap();
        fs::write(&path, b"corrupt garbage").unwrap(); // on-disk vault is corrupt

        let result = restore_vault_from_file(&path, &source);
        let main_after = fs::read(&path).unwrap();
        let recovered = read_vault(&path).and_then(|s| open_vault(b"backup pw", &s));
        for p in [&path, &bak, &source, &source_bak] {
            let _ = fs::remove_file(p);
        }

        result.expect("restore from a valid backup file must succeed");
        assert_eq!(
            main_after, source_bytes,
            "the vault must now equal the picked backup file"
        );
        assert_eq!(recovered.expect("restored vault must open"), b"backup body");
    }

    // R-03: restoring from a file that is not a vault must be refused and must
    // leave the existing (corrupt) vault untouched — never replace one
    // unreadable file with another.
    #[test]
    fn restore_vault_from_file_refuses_unparseable_source() {
        let dir = temp_dir();
        let path = dir.join("gabbro_io_restore_badsrc_test.gabbro");
        let source = dir.join("gabbro_io_restore_badsrc_source.gabbro");
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&source);

        fs::write(&path, b"corrupt main").unwrap();
        fs::write(&source, b"not a vault either").unwrap();

        let result = restore_vault_from_file(&path, &source);
        let main_after = fs::read(&path).unwrap();
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(&source);

        let err = result.expect_err("restoring from an unparseable file must fail");
        assert!(
            err.to_lowercase().contains("usable") || err.to_lowercase().contains("refused"),
            "error must explain the file is not a usable vault: {err}"
        );
        assert_eq!(
            main_after, b"corrupt main",
            "a refused restore must leave the existing vault untouched"
        );
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

        let sealed = seal_vault(passphrase, plaintext, None).unwrap();
        write_vault(&sealed, &path).unwrap();

        let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        let _ = fs::remove_file(&path);
        assert_eq!(mode, 0o600, "expected 0600, got {:#o}", mode);
    }

    // S-04: the export/JSON-export write path goes through atomic_write_0600,
    // which must not follow a pre-planted symlink at `<path>.tmp` and write the
    // (plaintext, for JSON export) bytes through to an attacker-chosen target.
    #[cfg(unix)]
    #[test]
    fn atomic_write_0600_refuses_symlinked_temp() {
        use std::os::unix::fs::symlink;

        let dir = temp_dir();
        let target = dir.join("gabbro_io_atomic_target.json");
        let tmp = dir.join("gabbro_io_atomic_target.json.tmp");
        let victim = dir.join("gabbro_io_atomic_victim");
        let _ = fs::remove_file(&target);
        let _ = fs::remove_file(&tmp);
        let _ = fs::remove_file(&victim);
        fs::write(&victim, b"original").unwrap();
        symlink(&victim, &tmp).unwrap();

        let res = atomic_write_0600(&target, b"secret export bytes");
        let victim_after = fs::read(&victim).unwrap_or_default();

        let _ = fs::remove_file(&target);
        let _ = fs::remove_file(&tmp);
        let _ = fs::remove_file(&victim);

        assert!(
            res.is_err(),
            "must refuse to write through a symlinked temp"
        );
        assert_eq!(victim_after, b"original", "victim file must be untouched");
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

        let sealed = seal_vault(b"pw", b"body", None).unwrap();
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

        let sealed = seal_vault(b"pw", b"body", None).unwrap();
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
