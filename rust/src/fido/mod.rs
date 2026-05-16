//! FIDO2 hmac-secret integration via libfido2.
//!
//! Provides two operations:
//! - `register`: create a new FIDO2 credential on a YubiKey, returning a
//!   `YubiKeyRecord` ready to store in the vault header.
//! - `get_hmac_secret`: given a `YubiKeyRecord`, obtain the 32-byte
//!   hmac-secret output from the YubiKey for use in `combine_yubikey`.

use crate::vault::file_format::YubiKeyRecord;

pub mod device;

/// Relying party ID used for all Gabbro FIDO2 credentials.
pub const RP_ID: &str = "app.gabbro.gabbro";

/// Register a new FIDO2 credential on the YubiKey at `device_path`.
///
/// Returns a `YubiKeyRecord` containing the credential ID and a fresh
/// random 32-byte salt. The salt must be stored in the vault header.
/// On each unlock, the same salt is sent back to the YubiKey to
/// reproduce the hmac-secret output deterministically.
///
/// `pin` is the FIDO2 PIN set on the YubiKey.
pub fn register(device_path: &str, pin: &str) -> Result<YubiKeyRecord, String> {
    device::register_credential(device_path, pin)
}

/// Obtain the 32-byte hmac-secret output from the YubiKey.
///
/// `record` is the `YubiKeyRecord` stored in the vault header for this key.
/// `pin` is the FIDO2 PIN set on the YubiKey.
///
/// The returned bytes are fed directly into `combine_yubikey` alongside
/// the Argon2id output to reconstruct the vault key.
pub fn get_hmac_secret(
    device_path: &str,
    record: &YubiKeyRecord,
    pin: &str,
) -> Result<[u8; 32], String> {
    device::get_hmac_secret(device_path, record, pin)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;

    #[test]
    fn rp_id_is_correct() {
        assert_eq!(RP_ID, "app.gabbro.gabbro");
    }

    #[test]
    #[serial]
    #[ignore] // requires YubiKey hardware; set GABBRO_TEST_PIN and GABBRO_TEST_DEVICE
    fn register_returns_yubikey_record() {
        let pin = std::env::var("GABBRO_TEST_PIN")
            .expect("GABBRO_TEST_PIN must be set");
        let device = std::env::var("GABBRO_TEST_DEVICE")
            .unwrap_or_else(|_| "/dev/hidraw5".to_string());
        let record = register(&device, &pin)
            .expect("registration should succeed with YubiKey present");
        assert!(!record.credential_id.is_empty());
        assert_eq!(record.salt.len(), 32);
    }

    #[test]
    #[serial]
    #[ignore] // requires YubiKey hardware; set GABBRO_TEST_PIN and GABBRO_TEST_DEVICE
    fn get_hmac_secret_is_deterministic() {
        let pin = std::env::var("GABBRO_TEST_PIN")
            .expect("GABBRO_TEST_PIN must be set");
        let device = std::env::var("GABBRO_TEST_DEVICE")
            .unwrap_or_else(|_| "/dev/hidraw5".to_string());
        let record = register(&device, &pin)
            .expect("registration should succeed");
        let out1 = get_hmac_secret(&device, &record, &pin)
            .expect("first hmac-secret should succeed");
        let out2 = get_hmac_secret(&device, &record, &pin)
            .expect("second hmac-secret should succeed");
        assert_eq!(out1, out2, "same salt must produce same hmac-secret");
    }
}