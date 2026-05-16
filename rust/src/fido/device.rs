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
        if r != FIDO_OK as i32 {
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
        let r = fido_cred_set_type(cred, COSE_ES256 as i32);
        if r != FIDO_OK as i32 {
            return Err(format!("fido_cred_set_type failed: {r}"));
        }

        let r = fido_cred_set_clientdata_hash(
            cred,
            client_data_hash.as_ptr(),
            client_data_hash.len(),
        );
        if r != FIDO_OK as i32 {
            return Err(format!("fido_cred_set_clientdata_hash failed: {r}"));
        }

        let r = fido_cred_set_rp(cred, rp_id_c.as_ptr(), rp_name_c.as_ptr());
        if r != FIDO_OK as i32 {
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
        if r != FIDO_OK as i32 {
            return Err(format!("fido_cred_set_user failed: {r}"));
        }

        // Enable hmac-secret extension on the credential.
        let r = fido_cred_set_extensions(cred, FIDO_EXT_HMAC_SECRET as i32);
        if r != FIDO_OK as i32 {
            return Err(format!("fido_cred_set_extensions failed: {r}"));
        }

        // Make the credential — this triggers the YubiKey tap.
        let r = fido_dev_make_cred(dev, cred, pin_c.as_ptr());
        if r != FIDO_OK as i32 {
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

        Ok(YubiKeyRecord { credential_id, salt })
    }
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
        if r != FIDO_OK as i32 {
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
        if r != FIDO_OK as i32 {
            return Err(format!("fido_assert_set_clientdata_hash failed: {r}"));
        }

        let r = fido_assert_set_rp(assert, rp_id_c.as_ptr());
        if r != FIDO_OK as i32 {
            return Err(format!("fido_assert_set_rp failed: {r}"));
        }

        // Restrict assertion to our stored credential ID.
        let r = fido_assert_allow_cred(
            assert,
            record.credential_id.as_ptr(),
            record.credential_id.len(),
        );
        if r != FIDO_OK as i32 {
            return Err(format!("fido_assert_allow_cred failed: {r}"));
        }

        // Enable hmac-secret extension and set our stored salt.
        let r = fido_assert_set_extensions(assert, FIDO_EXT_HMAC_SECRET as i32);
        if r != FIDO_OK as i32 {
            return Err(format!("fido_assert_set_extensions failed: {r}"));
        }

        let r = fido_assert_set_hmac_salt(assert, record.salt.as_ptr(), record.salt.len());
        if r != FIDO_OK as i32 {
            return Err(format!("fido_assert_set_hmac_salt failed: {r}"));
        }

        // Get the assertion — this triggers the YubiKey tap.
        let r = fido_dev_get_assert(dev, assert, pin_c.as_ptr());
        if r != FIDO_OK as i32 {
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