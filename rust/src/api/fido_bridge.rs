//! Linux bridge for FIDO2 hardware key operations via libfido2.
//!
//! These functions are called directly by Flutter on Linux. On Android,
//! the equivalent operations are handled by yubikit-android via the
//! `app.gabbro.gabbro/yubikey` MethodChannel — these functions are never
//! called there, but Android stubs are provided so the generated Dart
//! bindings compile on all platforms.

/// Credential record returned by `fido_register`.
pub struct FidoCredentialData {
    pub credential_id: Vec<u8>,
    pub salt: Vec<u8>,
}

/// One registered YubiKey record passed to `fido_get_hmac_secret_any`.
pub struct FidoRecordInput {
    pub credential_id: Vec<u8>,
    /// 32-byte HKDF salt stored in the vault header for this credential.
    pub salt: Vec<u8>,
}

/// Result of a multi-credential hmac-secret assertion.
pub struct FidoHmacMatch {
    /// 32-byte hmac-secret output for the matched credential.
    pub hmac: Vec<u8>,
    /// Credential ID of the key that responded.
    pub credential_id: Vec<u8>,
}

// ── Linux implementations ─────────────────────────────────────────────────────

#[cfg(not(target_os = "android"))]
/// Enumerate FIDO2 HID devices and return their paths (e.g. `/dev/hidraw5`).
///
/// Returns an empty list when no FIDO2 devices are present — not an error.
/// Sync — fast device scan, no I/O.
#[flutter_rust_bridge::frb(sync)]
pub fn fido_list_devices() -> Result<Vec<String>, String> {
    use std::ffi::CStr;

    use libfido2_sys::*;

    const MAX_DEVICES: usize = 16;
    unsafe {
        fido_init(0);
        let devlist = fido_dev_info_new(MAX_DEVICES);
        if devlist.is_null() {
            return Err("fido_dev_info_new failed".to_string());
        }
        let mut olen: usize = 0;
        let r = fido_dev_info_manifest(devlist, MAX_DEVICES, &mut olen);
        if r != FIDO_OK {
            fido_dev_info_free(&mut (devlist as *mut _), MAX_DEVICES);
            return Err(format!("fido_dev_info_manifest failed: {r}"));
        }
        let mut paths = Vec::with_capacity(olen);
        for i in 0..olen {
            let info = fido_dev_info_ptr(devlist, i);
            if info.is_null() {
                continue;
            }
            let path_ptr = fido_dev_info_path(info);
            if path_ptr.is_null() {
                continue;
            }
            if let Ok(s) = CStr::from_ptr(path_ptr).to_str() {
                paths.push(s.to_string());
            }
        }
        fido_dev_info_free(&mut (devlist as *mut _), MAX_DEVICES);
        Ok(paths)
    }
}

#[cfg(not(target_os = "android"))]
/// Register a new FIDO2 credential on the YubiKey at `device_path`.
///
/// Triggers one YubiKey tap. Returns credential ID and a fresh random
/// 32-byte salt — both must be stored in the vault header.
/// Async — blocks until the user taps the key.
pub async fn fido_register(device_path: String, pin: String) -> Result<FidoCredentialData, String> {
    let record = crate::fido::register(&device_path, &pin)?;
    Ok(FidoCredentialData {
        credential_id: record.credential_id,
        salt: record.salt.to_vec(),
    })
}

#[cfg(not(target_os = "android"))]
/// Obtain the 32-byte hmac-secret output from the YubiKey.
///
/// `credential_id` and `salt` come from `FidoCredentialData` (stored in the
/// vault header). Triggers one YubiKey tap.
/// Async — blocks until the user taps the key.
pub async fn fido_get_hmac_secret(
    device_path: String,
    credential_id: Vec<u8>,
    salt: Vec<u8>,
    pin: String,
) -> Result<Vec<u8>, String> {
    use crate::vault::file_format::YubiKeyRecord;

    let salt_arr: [u8; 32] = salt
        .try_into()
        .map_err(|_| "salt must be exactly 32 bytes".to_string())?;
    let record = YubiKeyRecord {
        credential_id,
        salt: salt_arr,
        key_blob: vec![],
    };
    let hmac = crate::fido::get_hmac_secret(&device_path, &record, &pin)?;
    Ok(hmac.to_vec())
}

#[cfg(not(target_os = "android"))]
/// Obtain the 32-byte hmac-secret for whichever registered YubiKey is inserted.
///
/// For 2 records, sends a single CTAP2 assertion with both credential IDs in
/// the `allowList` and a 64-byte combined salt. The YubiKey taps once and the
/// matching half is extracted. For >2 records, C(n,2) pair attempts are tried
/// until the inserted key is identified; non-matching pairs return immediately
/// without a tap. For 1 record, falls back to the single-credential path.
/// Async — blocks until the user taps the key.
pub async fn fido_get_hmac_secret_any(
    device_path: String,
    records: Vec<FidoRecordInput>,
    pin: String,
) -> Result<FidoHmacMatch, String> {
    use crate::vault::file_format::YubiKeyRecord;

    let yubikey_records: Vec<YubiKeyRecord> = records
        .into_iter()
        .map(|r| {
            let salt: [u8; 32] = r
                .salt
                .try_into()
                .map_err(|_| "salt must be exactly 32 bytes".to_string())?;
            Ok(YubiKeyRecord {
                credential_id: r.credential_id,
                salt,
                key_blob: vec![],
            })
        })
        .collect::<Result<Vec<_>, String>>()?;

    let m = crate::fido::get_hmac_secret_any_of(&device_path, &yubikey_records, &pin)?;

    Ok(FidoHmacMatch {
        hmac: m.hmac.to_vec(),
        credential_id: m.credential_id,
    })
}

// ── Android stubs (never called; Flutter guards with Platform.isLinux) ─────────

#[cfg(target_os = "android")]
#[flutter_rust_bridge::frb(sync)]
pub fn fido_list_devices() -> Result<Vec<String>, String> {
    Err("fido_list_devices is not available on Android".to_string())
}

#[cfg(target_os = "android")]
pub async fn fido_register(
    _device_path: String,
    _pin: String,
) -> Result<FidoCredentialData, String> {
    Err("fido_register is not available on Android".to_string())
}

#[cfg(target_os = "android")]
pub async fn fido_get_hmac_secret(
    _device_path: String,
    _credential_id: Vec<u8>,
    _salt: Vec<u8>,
    _pin: String,
) -> Result<Vec<u8>, String> {
    Err("fido_get_hmac_secret is not available on Android".to_string())
}

#[cfg(target_os = "android")]
pub async fn fido_get_hmac_secret_any(
    _device_path: String,
    _records: Vec<FidoRecordInput>,
    _pin: String,
) -> Result<FidoHmacMatch, String> {
    Err("fido_get_hmac_secret_any is not available on Android".to_string())
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;

    #[test]
    #[cfg(not(target_os = "android"))]
    fn fido_list_devices_returns_ok() {
        // No hardware required — returns empty list when no FIDO2 devices present.
        let result = fido_list_devices();
        assert!(
            result.is_ok(),
            "fido_list_devices should not error: {result:?}"
        );
    }

    #[test]
    #[serial]
    #[ignore] // requires YubiKey; set GABBRO_TEST_PIN and GABBRO_TEST_DEVICE
    #[cfg(not(target_os = "android"))]
    fn fido_register_returns_credential_data() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let pin = std::env::var("GABBRO_TEST_PIN").expect("GABBRO_TEST_PIN must be set");
        let device =
            std::env::var("GABBRO_TEST_DEVICE").unwrap_or_else(|_| "/dev/hidraw5".to_string());
        println!("\n>>> TAP your YubiKey to register...");
        let result = rt
            .block_on(fido_register(device, pin))
            .expect("fido_register should succeed");
        assert!(
            !result.credential_id.is_empty(),
            "credential_id must not be empty"
        );
        assert_eq!(result.salt.len(), 32, "salt must be 32 bytes");
    }

    #[test]
    #[serial]
    #[ignore] // requires YubiKey; set GABBRO_TEST_PIN and GABBRO_TEST_DEVICE
    #[cfg(not(target_os = "android"))]
    fn fido_get_hmac_secret_returns_32_bytes() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let pin = std::env::var("GABBRO_TEST_PIN").expect("GABBRO_TEST_PIN must be set");
        let device =
            std::env::var("GABBRO_TEST_DEVICE").unwrap_or_else(|_| "/dev/hidraw5".to_string());
        println!("\n>>> TAP your YubiKey to register (tap 1/2)...");
        let cred = rt
            .block_on(fido_register(device.clone(), pin.clone()))
            .expect("register should succeed");
        println!(">>> TAP your YubiKey for hmac-secret (tap 2/2)...");
        let hmac = rt
            .block_on(fido_get_hmac_secret(
                device,
                cred.credential_id,
                cred.salt,
                pin,
            ))
            .expect("get_hmac_secret should succeed");
        assert_eq!(hmac.len(), 32, "hmac-secret must be 32 bytes");
    }

    #[test]
    #[serial]
    #[ignore] // requires YubiKey; set GABBRO_TEST_PIN and GABBRO_TEST_DEVICE
    #[cfg(not(target_os = "android"))]
    fn fido_get_hmac_secret_any_single_record_returns_32_bytes() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let pin = std::env::var("GABBRO_TEST_PIN").expect("GABBRO_TEST_PIN must be set");
        let device =
            std::env::var("GABBRO_TEST_DEVICE").unwrap_or_else(|_| "/dev/hidraw5".to_string());
        println!("\n>>> TAP your YubiKey to register (tap 1/2)...");
        let cred = rt
            .block_on(fido_register(device.clone(), pin.clone()))
            .expect("register should succeed");
        let record = FidoRecordInput {
            credential_id: cred.credential_id,
            salt: cred.salt,
        };
        println!(">>> TAP your YubiKey for hmac-secret-any (tap 2/2)...");
        let result = rt
            .block_on(fido_get_hmac_secret_any(device, vec![record], pin))
            .expect("fido_get_hmac_secret_any should succeed");
        assert_eq!(result.hmac.len(), 32, "hmac must be 32 bytes");
        assert!(
            !result.credential_id.is_empty(),
            "credential_id must not be empty"
        );
    }
}
