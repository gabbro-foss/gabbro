//! FIDO2 hmac-secret via libfido2.

use crate::vault::file_format::YubiKeyRecord;

pub mod device;
pub use device::{get_hmac_secret_any_of, HmacMatch};

/// Relying party ID used for all Gabbro FIDO2 credentials.
pub const RP_ID: &str = "app.gabbro.gabbro";

/// The fresh salt in the record must be stored: the same salt reproduces the
/// hmac-secret on every unlock.
pub fn register(device_path: &str, pin: &str) -> Result<YubiKeyRecord, String> {
    device::register_credential(device_path, pin)
}

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
        let pin = std::env::var("GABBRO_TEST_PIN").expect("GABBRO_TEST_PIN must be set");
        let device =
            std::env::var("GABBRO_TEST_DEVICE").unwrap_or_else(|_| "/dev/hidraw5".to_string());
        println!("\n>>> TAP your YubiKey to register a credential...");
        let record =
            register(&device, &pin).expect("registration should succeed with YubiKey present");
        assert!(!record.credential_id.is_empty());
        assert_eq!(record.salt.len(), 32);
    }

    #[test]
    #[serial]
    #[ignore] // requires YubiKey hardware; set GABBRO_TEST_PIN and GABBRO_TEST_DEVICE
    fn get_hmac_secret_is_deterministic() {
        let pin = std::env::var("GABBRO_TEST_PIN").expect("GABBRO_TEST_PIN must be set");
        let device =
            std::env::var("GABBRO_TEST_DEVICE").unwrap_or_else(|_| "/dev/hidraw5".to_string());
        println!("\n>>> TAP your YubiKey to register a credential (tap 1/3)...");
        let record = register(&device, &pin).expect("registration should succeed");
        println!(">>> TAP your YubiKey for first hmac-secret assertion (tap 2/3)...");
        let out1 =
            get_hmac_secret(&device, &record, &pin).expect("first hmac-secret should succeed");
        println!(">>> TAP your YubiKey for second hmac-secret assertion (tap 3/3)...");
        let out2 =
            get_hmac_secret(&device, &record, &pin).expect("second hmac-secret should succeed");
        assert_eq!(out1, out2, "same salt must produce same hmac-secret");
    }
}
