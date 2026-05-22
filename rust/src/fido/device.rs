//! Raw libfido2 FFI calls for credential registration and hmac-secret retrieval.

use std::ffi::CString;
use std::ptr;

use libfido2_sys::*;
use rand::RngCore;

use crate::vault::file_format::YubiKeyRecord;

use super::RP_ID;

/// Register a new FIDO2 credential on the YubiKey at `device_path`.
pub fn register_credential(device_path: &str, pin: &str) -> Result<YubiKeyRecord, String> {
    // A random 32-byte client data hash stands in for a real WebAuthn
    // client data hash. We are our own relying party; the value is not
    // verified externally.
    let mut client_data_hash = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut client_data_hash);

    // A fixed user ID is fine — Gabbro has one user per vault.
    let user_id = b"gabbro-user";

    let device_path_c = CString::new(device_path).map_err(|e| e.to_string())?;
    let pin_c = CString::new(pin).map_err(|e| e.to_string())?;
    let rp_id_c = CString::new(RP_ID).map_err(|e| e.to_string())?;
    let rp_name_c = CString::new("Gabbro").map_err(|e| e.to_string())?;
    let user_name_c = CString::new("gabbro-user").map_err(|e| e.to_string())?;

    unsafe {
        fido_init(0);

        // --- Device ---
        let dev = fido_dev_new();
        if dev.is_null() {
            return Err("fido_dev_new failed".to_string());
        }

        let r = fido_dev_open(dev, device_path_c.as_ptr());
        if r != FIDO_OK {
            fido_dev_free(&mut (dev as *mut _));
            return Err(format!("fido_dev_open failed: {r}"));
        }

        // --- Credential ---
        let cred = fido_cred_new();
        if cred.is_null() {
            fido_dev_close(dev);
            fido_dev_free(&mut (dev as *mut _));
            return Err("fido_cred_new failed".to_string());
        }

        // ES256 = COSE algorithm -7 (ECDSA P-256). Required by CTAP2.
        let r = fido_cred_set_type(cred, COSE_ES256);
        if r != FIDO_OK {
            return Err(format!("fido_cred_set_type failed: {r}"));
        }

        let r =
            fido_cred_set_clientdata_hash(cred, client_data_hash.as_ptr(), client_data_hash.len());
        if r != FIDO_OK {
            return Err(format!("fido_cred_set_clientdata_hash failed: {r}"));
        }

        let r = fido_cred_set_rp(cred, rp_id_c.as_ptr(), rp_name_c.as_ptr());
        if r != FIDO_OK {
            return Err(format!("fido_cred_set_rp failed: {r}"));
        }

        let r = fido_cred_set_user(
            cred,
            user_id.as_ptr(),
            user_id.len(),
            user_name_c.as_ptr(),
            ptr::null(),
            ptr::null(),
        );
        if r != FIDO_OK {
            return Err(format!("fido_cred_set_user failed: {r}"));
        }

        // Enable hmac-secret extension on the credential.
        let r = fido_cred_set_extensions(cred, FIDO_EXT_HMAC_SECRET);
        if r != FIDO_OK {
            return Err(format!("fido_cred_set_extensions failed: {r}"));
        }

        // Make the credential — this triggers the YubiKey tap.
        let r = fido_dev_make_cred(dev, cred, pin_c.as_ptr());
        if r != FIDO_OK {
            fido_cred_free(&mut (cred as *mut _));
            fido_dev_close(dev);
            fido_dev_free(&mut (dev as *mut _));
            return Err(format!("fido_dev_make_cred failed: {r}"));
        }

        // Extract the credential ID.
        let id_ptr = fido_cred_id_ptr(cred);
        let id_len = fido_cred_id_len(cred);
        if id_ptr.is_null() || id_len == 0 {
            fido_cred_free(&mut (cred as *mut _));
            fido_dev_close(dev);
            fido_dev_free(&mut (dev as *mut _));
            return Err("credential ID is empty".to_string());
        }
        let credential_id = std::slice::from_raw_parts(id_ptr, id_len).to_vec();

        // Generate a fresh random 32-byte salt — stored in the vault header.
        let mut salt = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut salt);

        fido_cred_free(&mut (cred as *mut _));
        fido_dev_close(dev);
        fido_dev_free(&mut (dev as *mut _));

        Ok(YubiKeyRecord {
            credential_id,
            salt,
            key_blob: vec![],
        })
    }
}

/// Matched credential and its hmac-secret output from a multi-credential assertion.
#[derive(Debug)]
pub struct HmacMatch {
    /// 32-byte hmac-secret output for the matched credential.
    pub hmac: [u8; 32],
    /// Credential ID of the key that responded.
    pub credential_id: Vec<u8>,
}

/// Obtain the 32-byte hmac-secret output from the YubiKey.
pub fn get_hmac_secret(
    device_path: &str,
    record: &YubiKeyRecord,
    pin: &str,
) -> Result<[u8; 32], String> {
    let mut client_data_hash = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut client_data_hash);

    let device_path_c = CString::new(device_path).map_err(|e| e.to_string())?;
    let pin_c = CString::new(pin).map_err(|e| e.to_string())?;
    let rp_id_c = CString::new(RP_ID).map_err(|e| e.to_string())?;

    unsafe {
        fido_init(0);

        // --- Device ---
        let dev = fido_dev_new();
        if dev.is_null() {
            return Err("fido_dev_new failed".to_string());
        }

        let r = fido_dev_open(dev, device_path_c.as_ptr());
        if r != FIDO_OK {
            fido_dev_free(&mut (dev as *mut _));
            return Err(format!("fido_dev_open failed: {r}"));
        }

        // --- Assertion ---
        let assert = fido_assert_new();
        if assert.is_null() {
            fido_dev_close(dev);
            fido_dev_free(&mut (dev as *mut _));
            return Err("fido_assert_new failed".to_string());
        }

        let r = fido_assert_set_clientdata_hash(
            assert,
            client_data_hash.as_ptr(),
            client_data_hash.len(),
        );
        if r != FIDO_OK {
            return Err(format!("fido_assert_set_clientdata_hash failed: {r}"));
        }

        let r = fido_assert_set_rp(assert, rp_id_c.as_ptr());
        if r != FIDO_OK {
            return Err(format!("fido_assert_set_rp failed: {r}"));
        }

        // Restrict assertion to our stored credential ID.
        let r = fido_assert_allow_cred(
            assert,
            record.credential_id.as_ptr(),
            record.credential_id.len(),
        );
        if r != FIDO_OK {
            return Err(format!("fido_assert_allow_cred failed: {r}"));
        }

        // Enable hmac-secret extension and set our stored salt.
        let r = fido_assert_set_extensions(assert, FIDO_EXT_HMAC_SECRET);
        if r != FIDO_OK {
            return Err(format!("fido_assert_set_extensions failed: {r}"));
        }

        let r = fido_assert_set_hmac_salt(assert, record.salt.as_ptr(), record.salt.len());
        if r != FIDO_OK {
            return Err(format!("fido_assert_set_hmac_salt failed: {r}"));
        }

        // Get the assertion — this triggers the YubiKey tap.
        let r = fido_dev_get_assert(dev, assert, pin_c.as_ptr());
        if r != FIDO_OK {
            fido_assert_free(&mut (assert as *mut _));
            fido_dev_close(dev);
            fido_dev_free(&mut (dev as *mut _));
            return Err(format!("fido_dev_get_assert failed: {r}"));
        }

        // Extract the hmac-secret output (32 bytes, assertion index 0).
        let secret_ptr = fido_assert_hmac_secret_ptr(assert, 0);
        let secret_len = fido_assert_hmac_secret_len(assert, 0);

        if secret_ptr.is_null() || secret_len != 32 {
            fido_assert_free(&mut (assert as *mut _));
            fido_dev_close(dev);
            fido_dev_free(&mut (dev as *mut _));
            return Err(format!(
                "unexpected hmac-secret length: {secret_len} (expected 32)"
            ));
        }

        let secret_slice = std::slice::from_raw_parts(secret_ptr, 32);
        let mut output = [0u8; 32];
        output.copy_from_slice(secret_slice);

        fido_assert_free(&mut (assert as *mut _));
        fido_dev_close(dev);
        fido_dev_free(&mut (dev as *mut _));

        Ok(output)
    }
}

/// Two-credential assertion using a 64-byte combined salt.
///
/// Both credential IDs go into the CTAP2 `allowList`. The 64-byte salt is
/// `records[0].salt ∥ records[1].salt`. The YubiKey taps once, picks whichever
/// credential it owns, and returns 64 bytes of hmac-secret output. We read
/// `fido_assert_id_ptr` to identify the matched credential and extract the
/// correct 32-byte half.
pub fn get_hmac_secret_for_pair(
    device_path: &str,
    records: [&YubiKeyRecord; 2],
    pin: &str,
) -> Result<HmacMatch, String> {
    let mut combined_salt = [0u8; 64];
    combined_salt[..32].copy_from_slice(&records[0].salt);
    combined_salt[32..].copy_from_slice(&records[1].salt);

    let mut client_data_hash = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut client_data_hash);

    let device_path_c = CString::new(device_path).map_err(|e| e.to_string())?;
    let pin_c = CString::new(pin).map_err(|e| e.to_string())?;
    let rp_id_c = CString::new(RP_ID).map_err(|e| e.to_string())?;

    unsafe {
        fido_init(0);

        let dev = fido_dev_new();
        if dev.is_null() {
            return Err("fido_dev_new failed".to_string());
        }

        let r = fido_dev_open(dev, device_path_c.as_ptr());
        if r != FIDO_OK {
            fido_dev_free(&mut (dev as *mut _));
            return Err(format!("fido_dev_open failed: {r}"));
        }

        let assert = fido_assert_new();
        if assert.is_null() {
            fido_dev_close(dev);
            fido_dev_free(&mut (dev as *mut _));
            return Err("fido_assert_new failed".to_string());
        }

        let r = fido_assert_set_clientdata_hash(
            assert,
            client_data_hash.as_ptr(),
            client_data_hash.len(),
        );
        if r != FIDO_OK {
            return Err(format!("fido_assert_set_clientdata_hash failed: {r}"));
        }

        let r = fido_assert_set_rp(assert, rp_id_c.as_ptr());
        if r != FIDO_OK {
            return Err(format!("fido_assert_set_rp failed: {r}"));
        }

        // Both credentials in the allowList — key picks whichever it owns.
        for record in &records {
            let r = fido_assert_allow_cred(
                assert,
                record.credential_id.as_ptr(),
                record.credential_id.len(),
            );
            if r != FIDO_OK {
                return Err(format!("fido_assert_allow_cred failed: {r}"));
            }
        }

        let r = fido_assert_set_extensions(assert, FIDO_EXT_HMAC_SECRET);
        if r != FIDO_OK {
            return Err(format!("fido_assert_set_extensions failed: {r}"));
        }

        // 64-byte salt → 64-byte output (two independent 32-byte HMACs).
        let r = fido_assert_set_hmac_salt(assert, combined_salt.as_ptr(), combined_salt.len());
        if r != FIDO_OK {
            return Err(format!("fido_assert_set_hmac_salt failed: {r}"));
        }

        // One tap — the YubiKey self-identifies which credential it owns.
        let r = fido_dev_get_assert(dev, assert, pin_c.as_ptr());
        if r != FIDO_OK {
            fido_assert_free(&mut (assert as *mut _));
            fido_dev_close(dev);
            fido_dev_free(&mut (dev as *mut _));
            return Err(format!("fido_dev_get_assert failed: {r}"));
        }

        // Read which credential matched (assertion statement index 0).
        let id_ptr = fido_assert_id_ptr(assert, 0);
        let id_len = fido_assert_id_len(assert, 0);
        if id_ptr.is_null() || id_len == 0 {
            fido_assert_free(&mut (assert as *mut _));
            fido_dev_close(dev);
            fido_dev_free(&mut (dev as *mut _));
            return Err("assertion: matched credential ID is empty".to_string());
        }
        let matched_id = std::slice::from_raw_parts(id_ptr, id_len).to_vec();

        // Extract 64-byte hmac output.
        let secret_ptr = fido_assert_hmac_secret_ptr(assert, 0);
        let secret_len = fido_assert_hmac_secret_len(assert, 0);
        if secret_ptr.is_null() || secret_len != 64 {
            fido_assert_free(&mut (assert as *mut _));
            fido_dev_close(dev);
            fido_dev_free(&mut (dev as *mut _));
            return Err(format!(
                "unexpected hmac-secret length: {secret_len} (expected 64)"
            ));
        }
        let secret_slice = std::slice::from_raw_parts(secret_ptr, 64);

        // Pick the correct half: index 0 → first 32 bytes, index 1 → last 32 bytes.
        let (hmac_bytes, credential_id) = if matched_id == records[0].credential_id {
            let mut out = [0u8; 32];
            out.copy_from_slice(&secret_slice[..32]);
            (out, records[0].credential_id.clone())
        } else if matched_id == records[1].credential_id {
            let mut out = [0u8; 32];
            out.copy_from_slice(&secret_slice[32..]);
            (out, records[1].credential_id.clone())
        } else {
            fido_assert_free(&mut (assert as *mut _));
            fido_dev_close(dev);
            fido_dev_free(&mut (dev as *mut _));
            return Err("assertion credential ID does not match either record".to_string());
        };

        fido_assert_free(&mut (assert as *mut _));
        fido_dev_close(dev);
        fido_dev_free(&mut (dev as *mut _));

        Ok(HmacMatch {
            hmac: hmac_bytes,
            credential_id,
        })
    }
}

/// Dispatch to the appropriate hmac-secret strategy based on record count.
///
/// 1 record: single 32-byte salt assertion (existing path). 2 records:
/// `get_hmac_secret_for_pair` — one tap, 64-byte combined salt. >2 records:
/// try all C(n,2) pairs; non-matching pairs fail without a tap (CTAP2
/// NO_CREDENTIALS is returned before user interaction).
pub fn get_hmac_secret_any_of(
    device_path: &str,
    records: &[YubiKeyRecord],
    pin: &str,
) -> Result<HmacMatch, String> {
    match records.len() {
        0 => Err("no records provided".to_string()),
        1 => {
            let hmac = get_hmac_secret(device_path, &records[0], pin)?;
            Ok(HmacMatch {
                hmac,
                credential_id: records[0].credential_id.clone(),
            })
        }
        2 => get_hmac_secret_for_pair(device_path, [&records[0], &records[1]], pin),
        _ => {
            for i in 0..records.len() {
                for j in (i + 1)..records.len() {
                    match get_hmac_secret_for_pair(device_path, [&records[i], &records[j]], pin) {
                        Ok(m) => return Ok(m),
                        Err(_) => continue,
                    }
                }
            }
            Err("no matching FIDO2 credential found among registered records".to_string())
        }
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;

    fn fake_record() -> YubiKeyRecord {
        YubiKeyRecord {
            credential_id: vec![0xDE, 0xAD, 0xBE, 0xEF],
            salt: [0u8; 32],
            key_blob: vec![],
        }
    }

    #[test]
    fn get_hmac_secret_any_of_empty_records_errors() {
        let result = get_hmac_secret_any_of("/dev/null", &[], "pin");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("no records"));
    }

    #[test]
    #[serial]
    #[ignore] // requires YubiKey; set GABBRO_TEST_PIN and GABBRO_TEST_DEVICE
    fn get_hmac_secret_for_pair_matches_primary_key() {
        let pin = std::env::var("GABBRO_TEST_PIN").expect("GABBRO_TEST_PIN must be set");
        let device =
            std::env::var("GABBRO_TEST_DEVICE").unwrap_or_else(|_| "/dev/hidraw5".to_string());

        println!("\n>>> TAP your PRIMARY YubiKey to register (tap 1/2)...");
        let rec0 = register_credential(&device, &pin).expect("register_credential should succeed");

        println!(">>> TAP your PRIMARY YubiKey for pair hmac-secret (tap 2/2)...");
        let m = get_hmac_secret_for_pair(&device, [&rec0, &fake_record()], &pin)
            .expect("pair assertion should succeed");
        assert_eq!(
            m.credential_id, rec0.credential_id,
            "primary key should be matched"
        );
        assert_eq!(m.hmac.len(), 32);
    }

    #[test]
    #[serial]
    #[ignore] // requires two YubiKeys; set GABBRO_TEST_PIN, GABBRO_TEST_DEVICE, GABBRO_TEST_DEVICE2
    fn get_hmac_secret_any_of_finds_backup_key() {
        let pin = std::env::var("GABBRO_TEST_PIN").expect("GABBRO_TEST_PIN must be set");
        let dev1 =
            std::env::var("GABBRO_TEST_DEVICE").unwrap_or_else(|_| "/dev/hidraw5".to_string());
        let dev2 = std::env::var("GABBRO_TEST_DEVICE2").expect("GABBRO_TEST_DEVICE2 must be set");

        println!("\n>>> TAP PRIMARY to register (tap 1/3)...");
        let rec0 = register_credential(&dev1, &pin).expect("register primary");
        println!(">>> TAP BACKUP to register (tap 2/3)...");
        let rec1 = register_credential(&dev2, &pin).expect("register backup");

        println!(">>> TAP BACKUP to assert (tap 3/3)...");
        let m = get_hmac_secret_any_of(&dev2, &[rec0, rec1], &pin)
            .expect("any_of should find backup key");
        assert_eq!(m.hmac.len(), 32);
    }
}
