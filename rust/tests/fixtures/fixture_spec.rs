// `include!`d by both the harness and `examples/gen_fixtures.rs` so seal-time
// and asserted values cannot drift. Textually included, so: fully-qualified
// paths, no top-level `use`, and `#[allow(dead_code)]` on items one includer
// does not use.

const FIXTURE_PASSPHRASE: &[u8] = b"correct horse battery staple -- gabbro fixture";

/// Alias stored in the plaintext header of the multi-key fixtures.
#[allow(dead_code)]
const FIXTURE_ALIAS: &str = "Backward-Compat Fixture Vault";

/// Canary login entry baked into every fixture body. Opening a fixture and
/// recovering these exact values proves the body genuinely decrypted under the
/// current code path - not merely that the header parsed. Crucially, the rotation
/// test asserts this entry SURVIVES every key add/remove and version bump.
const CANARY_TITLE: &str = "gabbro-backward-compat-canary";
const CANARY_PASSWORD: &str = "canary-pw-do-not-change-7Hk2qZ";
#[allow(dead_code)]
const CANARY_FOLDER: &str = "Personal";

// Fake YubiKey bytes, safe to commit: they protect format compatibility, not
// secrets. credential_id lengths vary to exercise the variable-length encoding.
#[allow(dead_code)]
const YK1_CRED: &[u8] = &[0x11; 64];
#[allow(dead_code)]
const YK1_HMAC: &[u8; 32] = &[0xA1; 32];
#[allow(dead_code)]
const YK1_SALT: [u8; 32] = [0xB1; 32];

#[allow(dead_code)]
const YK2_CRED: &[u8] = &[0x22; 48];
#[allow(dead_code)]
const YK2_HMAC: &[u8; 32] = &[0xA2; 32];
#[allow(dead_code)]
const YK2_SALT: [u8; 32] = [0xB2; 32];

#[allow(dead_code)]
const YK3_CRED: &[u8] = &[0x33; 56];
#[allow(dead_code)]
const YK3_HMAC: &[u8; 32] = &[0xA3; 32];
#[allow(dead_code)]
const YK3_SALT: [u8; 32] = [0xB3; 32];

#[allow(dead_code)]
const YK4_CRED: &[u8] = &[0x44; 60];
#[allow(dead_code)]
const YK4_HMAC: &[u8; 32] = &[0xA4; 32];
#[allow(dead_code)]
const YK4_SALT: [u8; 32] = [0xB4; 32];

/// The canary login entry. Defined once so the generator seals exactly what the
/// harness asserts.
#[allow(dead_code)]
fn canary_entry() -> rust_lib_gabbro::vault::entry::VaultEntry {
    use rust_lib_gabbro::vault::entry::{EntryMeta, LoginEntry, VaultEntry};
    VaultEntry::Login(LoginEntry {
        meta: EntryMeta { field_times: Default::default(),
            history: Vec::new(),
            id: "00000000-0000-0000-0000-000000000001".to_string(),
            created_at: "2026-01-01T00:00:00Z".to_string(),
            updated_at: "2026-01-01T00:00:00Z".to_string(),
            folder: CANARY_FOLDER.to_string(),
        },
        title: CANARY_TITLE.to_string(),
        url: "https://example.test".to_string(),
        username: "fixture-user".to_string(),
        password: CANARY_PASSWORD.to_string(),
        notes: None,
        custom_fields: vec![],
        attachments: vec![],
        app_id: None,
        email: None,
    })
}

// Fixed bytes prove the FORMAT round-trips key material intact; they are not a
// signing-valid key pair. v11 fixtures are frozen without it.
#[allow(dead_code)]
const PASSKEY_CANARY_RP_ID: &str = "canary.example.test";
#[allow(dead_code)]
const PASSKEY_CANARY_PRIVATE_KEY: [u8; 32] = [0x55; 32];

/// The canary passkey entry sealed into v12+ fixtures.
#[allow(dead_code)]
fn canary_passkey_entry() -> rust_lib_gabbro::vault::entry::VaultEntry {
    use rust_lib_gabbro::vault::entry::{EntryMeta, PasskeyEntry, VaultEntry};
    VaultEntry::Passkey(PasskeyEntry {
        meta: EntryMeta {
            field_times: Default::default(),
            history: Vec::new(),
            id: "00000000-0000-0000-0000-000000000002".to_string(),
            created_at: "2026-01-01T00:00:00Z".to_string(),
            updated_at: "2026-01-01T00:00:00Z".to_string(),
            folder: String::new(),
        },
        rp_id: PASSKEY_CANARY_RP_ID.to_string(),
        user_name: "fixture-user@example.test".to_string(),
        user_display_name: "Fixture User".to_string(),
        user_handle: vec![0x77; 16],
        credential_id: vec![0x66; 32],
        private_key: PASSKEY_CANARY_PRIVATE_KEY.to_vec(),
        public_key_cose: vec![0x88; 77],
        algorithm: -7,
        notes: None,
        custom_fields: vec![],
    })
}

/// The vault body every passphrase fixture seals: an empty vault plus the
/// canaries (login always; passkey from v12 on).
#[allow(dead_code)]
fn canary_body() -> rust_lib_gabbro::vault::serialization::VaultBody {
    let mut body = rust_lib_gabbro::vault::serialization::VaultBody::empty();
    body.entries.push(canary_entry());
    body.entries.push(canary_passkey_entry());
    body
}

/// The two keys (YK1 + YK2) a multi-key fixture is created with, in the
/// primitive `YubiKeyInitData` shape the Flutter app passes across the bridge.
#[allow(dead_code)]
fn multikey_init_keys() -> Vec<rust_lib_gabbro::api::vault_bridge::YubiKeyInitData> {
    use rust_lib_gabbro::api::vault_bridge::YubiKeyInitData;
    vec![
        YubiKeyInitData {
            credential_id: YK1_CRED.to_vec(),
            hmac_secret: YK1_HMAC.to_vec(),
            hkdf_salt: YK1_SALT.to_vec(),
        },
        YubiKeyInitData {
            credential_id: YK2_CRED.to_vec(),
            hmac_secret: YK2_HMAC.to_vec(),
            hkdf_salt: YK2_SALT.to_vec(),
        },
    ]
}
