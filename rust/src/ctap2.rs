//! CTAP2 command layer for the Linux virtual FIDO2 authenticator.
//!
//! Takes the payload of a reassembled CTAPHID CBOR message (command byte +
//! CBOR request), performs it, and returns status byte + CBOR response.
//! Map keys verified against CTAP 2.1 section 6.4 and OpenSK's response encoder.

use ciborium::value::Value;

const CMD_MAKE_CREDENTIAL: u8 = 0x01;
const CMD_GET_ASSERTION: u8 = 0x02;
const CMD_GET_INFO: u8 = 0x04;
const CTAP2_OK: u8 = 0x00;
const CTAP1_ERR_INVALID_COMMAND: u8 = 0x01;
const CTAP2_ERR_INVALID_CBOR: u8 = 0x12;
const CTAP2_ERR_MISSING_PARAMETER: u8 = 0x14;
const CTAP2_ERR_CREDENTIAL_EXCLUDED: u8 = 0x19;
const CTAP2_ERR_UNSUPPORTED_ALGORITHM: u8 = 0x26;
const CTAP2_ERR_OPERATION_DENIED: u8 = 0x27;
const CTAP2_ERR_NO_CREDENTIALS: u8 = 0x2e;
/// Matches libfido2's FIDO_MAXMSG default.
const MAX_MSG_SIZE: i32 = 2048;

/// Per-operation user consent. The daemon hands this to the Flutter layer,
/// which shows the consent screen (site, create/sign-in, approve/cancel);
/// every create and every assertion asks - no silent signing.
pub trait Consent {
    fn approve_create(&self, rp_id: &str, user_name: &str) -> bool;
    fn approve_assert(&self, rp_id: &str, user_name: &str) -> bool;
    /// Several accounts match a sign-in with no allow-list: the user picks
    /// one (index into `user_names`) or cancels (None). Mirrors Android's
    /// system picker, so the wrong account is never signed in silently.
    fn choose_account(&self, rp_id: &str, user_names: &[String]) -> Option<usize>;
}

/// What the daemon should do with a request before any signing. Either ask
/// the user (Dart shows the consent screen) or send these bytes straight back
/// (locked vault, no match, malformed - no user choice applies).
pub enum RequestPlan {
    Ask {
        is_create: bool,
        rp_id: String,
        accounts: Vec<String>,
    },
    Respond(Vec<u8>),
}

/// First half of the Dart-driven seam: parse and locate accounts, no crypto.
/// Ask when a user choice applies; Respond with the CTAP bytes otherwise
/// (locked, malformed, unsupported algorithm, no matching credential).
pub fn describe_request(payload: &[u8]) -> RequestPlan {
    match payload.first() {
        // getInfo carries no user choice - answer straight away.
        Some(&CMD_GET_INFO) => RequestPlan::Respond(get_info()),
        Some(&CMD_MAKE_CREDENTIAL) => match parse_create(&payload[1..]) {
            Ok(c) => RequestPlan::Ask {
                is_create: true,
                rp_id: c.rp_id,
                accounts: vec![c.user_name],
            },
            Err(bytes) => RequestPlan::Respond(bytes),
        },
        // Silent authentication (CTAP 2.1 options.up=false): a browser
        // pre-flight, answered with no user interaction - a consent dialog
        // here costs the user a second click per sign-in. AllowList probes
        // only: without one, answering would hand any site a signed
        // assertion for a discoverable credential with zero user involvement.
        Some(&CMD_GET_ASSERTION) if up_option_is_false(&payload[1..]) => {
            match assertion_matches(&payload[1..]) {
                Ok((_, mut matches)) if has_allow_list(&payload[1..]) => RequestPlan::Respond(
                    perform_assert_silent(matches.swap_remove(0), &c_hash(&payload[1..])),
                ),
                Ok(_) => RequestPlan::Respond(vec![CTAP2_ERR_NO_CREDENTIALS]),
                Err(bytes) => RequestPlan::Respond(bytes),
            }
        }
        Some(&CMD_GET_ASSERTION) => match assertion_matches(&payload[1..]) {
            Ok((rp_id, matches)) => RequestPlan::Ask {
                is_create: false,
                rp_id,
                accounts: matches.iter().map(|e| e.user_name.clone()).collect(),
            },
            Err(bytes) => RequestPlan::Respond(bytes),
        },
        _ => RequestPlan::Respond(vec![CTAP1_ERR_INVALID_COMMAND]),
    }
}

/// True when the getAssertion request carries a non-empty allowList (key 3).
fn has_allow_list(body: &[u8]) -> bool {
    let Ok(Value::Map(req)) = ciborium::de::from_reader::<Value, _>(body) else {
        return false;
    };
    matches!(int_key(&req, 3), Some(Value::Array(a)) if !a.is_empty())
}

/// True when the getAssertion options map (key 5) carries `up: false` -
/// the CTAP 2.1 silent-authentication marker.
fn up_option_is_false(body: &[u8]) -> bool {
    let Ok(Value::Map(req)) = ciborium::de::from_reader::<Value, _>(body) else {
        return false;
    };
    int_key(&req, 5)
        .and_then(|v| v.as_map())
        .and_then(|m| m.iter().find(|(k, _)| k.as_text() == Some("up")))
        .is_some_and(|(_, v)| *v == Value::Bool(false))
}

/// Second half: perform a user-approved request. `account_index` selects among
/// the accounts `describe_request` listed (ignored for a create). Re-parses
/// from the same payload, so describe and perform never disagree.
pub fn perform_approved(payload: &[u8], account_index: usize) -> Vec<u8> {
    match payload.first() {
        Some(&CMD_MAKE_CREDENTIAL) => match parse_create(&payload[1..]) {
            Ok(c) => perform_create(c),
            Err(bytes) => bytes,
        },
        Some(&CMD_GET_ASSERTION) => match assertion_matches(&payload[1..]) {
            Ok((_, mut matches)) if account_index < matches.len() => {
                perform_assert(matches.swap_remove(account_index), &c_hash(&payload[1..]))
            }
            Ok(_) => vec![CTAP2_ERR_NO_CREDENTIALS],
            Err(bytes) => bytes,
        },
        _ => vec![CTAP1_ERR_INVALID_COMMAND],
    }
}

/// The response for a user who cancelled at the consent screen.
pub fn denied_response() -> Vec<u8> {
    vec![CTAP2_ERR_OPERATION_DENIED]
}

/// Handle one CTAP2 request end to end (Rust drives consent via the trait -
/// used by tests and any in-process caller). getInfo needs no user choice;
/// everything else goes through the same describe -> consent -> perform seam
/// the Dart daemon uses.
pub fn handle_request(payload: &[u8], consent: &dyn Consent) -> Vec<u8> {
    if payload.first() == Some(&CMD_GET_INFO) {
        return get_info();
    }
    match describe_request(payload) {
        RequestPlan::Respond(bytes) => bytes,
        RequestPlan::Ask {
            is_create,
            rp_id,
            accounts,
        } => {
            let approved = if is_create {
                consent.approve_create(&rp_id, &accounts[0]).then_some(0)
            } else if accounts.len() == 1 {
                consent.approve_assert(&rp_id, &accounts[0]).then_some(0)
            } else {
                consent.choose_account(&rp_id, &accounts)
            };
            match approved {
                Some(i) => perform_approved(payload, i),
                None => denied_response(),
            }
        }
    }
}

/// Text field of a CBOR map under a text key.
fn text_field<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a str> {
    map.iter()
        .find(|(k, _)| k.as_text() == Some(key))
        .and_then(|(_, v)| v.as_text())
}

/// Integer-keyed entry of a CBOR map.
fn int_key(map: &[(Value, Value)], key: i128) -> Option<&Value> {
    map.iter()
        .find(|(k, _)| matches!(k, Value::Integer(i) if i128::from(*i) == key))
        .map(|(_, v)| v)
}

/// The fields a makeCredential needs, validated. The exclude-list is left in
/// the raw request and checked in `perform_create` (after consent).
struct CreateFields {
    rp_id: String,
    user_name: String,
    display_name: String,
    user_handle: Vec<u8>,
    raw: Vec<(Value, Value)>,
}

/// Parse and validate a makeCredential body. Err carries the CTAP response
/// bytes to send when no user choice applies (locked, malformed, missing
/// param, unsupported algorithm).
fn parse_create(body: &[u8]) -> Result<CreateFields, Vec<u8>> {
    if !crate::vault::session::is_vault_unlocked() {
        return Err(vec![CTAP2_ERR_OPERATION_DENIED]);
    }
    let Ok(Value::Map(req)) = ciborium::de::from_reader::<Value, _>(body) else {
        return Err(vec![CTAP2_ERR_INVALID_CBOR]);
    };
    let (Some(Value::Map(rp)), Some(Value::Map(user)), Some(Value::Array(params))) =
        (int_key(&req, 2), int_key(&req, 3), int_key(&req, 4))
    else {
        return Err(vec![CTAP2_ERR_MISSING_PARAMETER]);
    };
    let Some(rp_id) = text_field(rp, "id") else {
        return Err(vec![CTAP2_ERR_MISSING_PARAMETER]);
    };
    let (Some(user_name), Some(Value::Bytes(user_handle))) = (
        text_field(user, "name"),
        user.iter()
            .find(|(k, _)| k.as_text() == Some("id"))
            .map(|(_, v)| v),
    ) else {
        return Err(vec![CTAP2_ERR_MISSING_PARAMETER]);
    };
    let display_name = text_field(user, "displayName").unwrap_or(user_name);
    // The site must accept ES256; refusing here beats minting an unusable key.
    let es256_ok = params.iter().any(|p| {
        p.as_map().is_some_and(|m| {
            m.iter().any(|(k, v)| {
                k.as_text() == Some("alg") && matches!(v, Value::Integer(i) if i128::from(*i) == -7)
            })
        })
    });
    if !es256_ok {
        return Err(vec![CTAP2_ERR_UNSUPPORTED_ALGORITHM]);
    }
    Ok(CreateFields {
        rp_id: rp_id.to_string(),
        user_name: user_name.to_string(),
        display_name: display_name.to_string(),
        user_handle: user_handle.clone(),
        raw: req,
    })
}

/// Register an approved credential and build the makeCredential response.
fn perform_create(c: CreateFields) -> Vec<u8> {
    // excludeList (key 5): the site refuses a duplicate for this account.
    // Checked after consent - the user-presence gate the spec demands, so a
    // background process cannot silently probe which sites the user is on.
    if let Some(Value::Array(exclude)) = int_key(&c.raw, 5) {
        let ours = match crate::vault::session::session_passkeys_for_rp(&c.rp_id) {
            Ok(m) => m,
            Err(_) => return vec![CTAP2_ERR_OPERATION_DENIED],
        };
        let excluded = exclude.iter().any(|d| {
            d.as_map().is_some_and(|m| {
                m.iter().any(|(k, v)| {
                    k.as_text() == Some("id")
                        && matches!(v, Value::Bytes(b) if ours.iter().any(|e| e.credential_id == *b))
                })
            })
        });
        if excluded {
            return vec![CTAP2_ERR_CREDENTIAL_EXCLUDED];
        }
    }

    let parts = match crate::api::passkey_bridge::register_passkey_parts(
        &c.rp_id,
        c.user_name,
        c.display_name,
        c.user_handle,
    ) {
        Ok(p) => p,
        Err(_) => return vec![CTAP2_ERR_OPERATION_DENIED],
    };
    let map = Value::Map(vec![
        (Value::Integer(1.into()), Value::Text("none".into())),
        (Value::Integer(2.into()), Value::Bytes(parts.auth_data)),
        (Value::Integer(3.into()), Value::Map(vec![])),
    ]);
    let mut out = vec![CTAP2_OK];
    ciborium::ser::into_writer(&map, &mut out).expect("in-memory CBOR write cannot fail");
    out
}

/// The clientDataHash from a getAssertion body (key 2), or empty if absent.
fn c_hash(body: &[u8]) -> Vec<u8> {
    let Ok(Value::Map(req)) = ciborium::de::from_reader::<Value, _>(body) else {
        return Vec::new();
    };
    match int_key(&req, 2) {
        Some(Value::Bytes(h)) => h.clone(),
        _ => Vec::new(),
    }
}

/// The accounts that answer a getAssertion, after the site's allow-list. Err
/// carries the CTAP bytes for locked/malformed/no-match (no user choice).
#[allow(clippy::type_complexity)]
fn assertion_matches(
    body: &[u8],
) -> Result<(String, Vec<crate::vault::entry::PasskeyEntry>), Vec<u8>> {
    if !crate::vault::session::is_vault_unlocked() {
        return Err(vec![CTAP2_ERR_OPERATION_DENIED]);
    }
    let Ok(Value::Map(req)) = ciborium::de::from_reader::<Value, _>(body) else {
        return Err(vec![CTAP2_ERR_INVALID_CBOR]);
    };
    let Some(rp_id) = int_key(&req, 1).and_then(|v| v.as_text()) else {
        return Err(vec![CTAP2_ERR_MISSING_PARAMETER]);
    };
    if int_key(&req, 2).and_then(|v| v.as_bytes()).is_none() {
        return Err(vec![CTAP2_ERR_MISSING_PARAMETER]);
    }
    let mut matches = match crate::vault::session::session_passkeys_for_rp(rp_id) {
        Ok(m) => m,
        Err(_) => return Err(vec![CTAP2_ERR_OPERATION_DENIED]),
    };
    // allowList (key 3): the site names the credentials it will accept - its
    // choice wins, so the user is never signed into the wrong account.
    if let Some(Value::Array(allow)) = int_key(&req, 3) {
        if !allow.is_empty() {
            matches.retain(|e| {
                allow.iter().any(|d| {
                    d.as_map().is_some_and(|m| {
                        m.iter().any(|(k, v)| {
                            k.as_text() == Some("id")
                                && matches!(v, Value::Bytes(b) if *b == e.credential_id)
                        })
                    })
                })
            });
        }
    }
    if matches.is_empty() {
        return Err(vec![CTAP2_ERR_NO_CREDENTIALS]);
    }
    Ok((rp_id.to_string(), matches))
}

/// Sign an approved assertion and build the getAssertion response.
fn perform_assert(pk: crate::vault::entry::PasskeyEntry, hash: &[u8]) -> Vec<u8> {
    let parts = match crate::api::passkey_bridge::sign_passkey_assertion(&pk.meta.id, hash) {
        Ok(p) => p,
        Err(_) => return vec![CTAP2_ERR_OPERATION_DENIED],
    };
    assertion_response(
        parts.credential_id,
        parts.auth_data,
        parts.signature_der,
        parts.user_handle,
    )
}

/// Sign a silent assertion (options.up=false): same response shape, but the
/// authenticator data carries no UP/UV claim and no user was consulted. The
/// key never leaves this function.
fn perform_assert_silent(pk: crate::vault::entry::PasskeyEntry, hash: &[u8]) -> Vec<u8> {
    use crate::crypto::webauthn;
    let auth_data = webauthn::silent_assertion_authenticator_data(&pk.rp_id);
    let signature_der = match webauthn::sign_assertion(&pk.private_key, &auth_data, hash) {
        Ok(s) => s,
        Err(_) => return vec![CTAP2_ERR_OPERATION_DENIED],
    };
    assertion_response(
        pk.credential_id.clone(),
        auth_data,
        signature_der,
        pk.user_handle.clone(),
    )
}

/// The CTAP2 getAssertion response map shared by the consented and silent
/// paths.
fn assertion_response(
    credential_id: Vec<u8>,
    auth_data: Vec<u8>,
    signature_der: Vec<u8>,
    user_handle: Vec<u8>,
) -> Vec<u8> {
    let map = Value::Map(vec![
        (
            Value::Integer(1.into()),
            Value::Map(vec![
                (Value::Text("id".into()), Value::Bytes(credential_id)),
                (Value::Text("type".into()), Value::Text("public-key".into())),
            ]),
        ),
        (Value::Integer(2.into()), Value::Bytes(auth_data)),
        (Value::Integer(3.into()), Value::Bytes(signature_der)),
        // 0x04 user: spec-required for discoverable credentials; id only.
        (
            Value::Integer(4.into()),
            Value::Map(vec![(Value::Text("id".into()), Value::Bytes(user_handle))]),
        ),
    ]);
    let mut out = vec![CTAP2_OK];
    ciborium::ser::into_writer(&map, &mut out).expect("in-memory CBOR write cannot fail");
    out
}

/// authenticatorGetInfo: a fixed self-description; touches nothing secret.
fn get_info() -> Vec<u8> {
    let options = Value::Map(vec![
        (Value::Text("rk".into()), Value::Bool(true)),
        (Value::Text("up".into()), Value::Bool(true)),
        (Value::Text("uv".into()), Value::Bool(true)),
    ]);
    let map = Value::Map(vec![
        (
            Value::Integer(1.into()),
            Value::Array(vec![
                Value::Text("FIDO_2_0".into()),
                Value::Text("FIDO_2_1".into()),
            ]),
        ),
        (Value::Integer(3.into()), Value::Bytes(vec![0u8; 16])),
        (Value::Integer(4.into()), options),
        (
            Value::Integer(5.into()),
            Value::Integer(MAX_MSG_SIZE.into()),
        ),
    ]);
    let mut out = vec![CTAP2_OK];
    ciborium::ser::into_writer(&map, &mut out).expect("in-memory CBOR write cannot fail");
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::vault::save_vault;
    use crate::api::vault_bridge::{list_entry_summaries, lock_vault, unlock_vault};
    use crate::vault::serialization::VaultBody;
    use ciborium::value::Value;
    use serial_test::serial;

    /// Approves everything: the consent screen's "Approve" in test form.
    struct Approve;
    impl Consent for Approve {
        fn approve_create(&self, _rp_id: &str, _user_name: &str) -> bool {
            true
        }
        fn approve_assert(&self, _rp_id: &str, _user_name: &str) -> bool {
            true
        }
        fn choose_account(&self, _rp_id: &str, _user_names: &[String]) -> Option<usize> {
            Some(0)
        }
    }

    /// Refuses everything: the consent screen's "Cancel" in test form.
    struct Deny;
    impl Consent for Deny {
        fn approve_create(&self, _rp_id: &str, _user_name: &str) -> bool {
            false
        }
        fn approve_assert(&self, _rp_id: &str, _user_name: &str) -> bool {
            false
        }
        fn choose_account(&self, _rp_id: &str, _user_names: &[String]) -> Option<usize> {
            None
        }
    }

    /// Panics if consulted: proves an operation never reached the user.
    struct NeverAsked;
    impl Consent for NeverAsked {
        fn approve_create(&self, _rp_id: &str, _user_name: &str) -> bool {
            panic!("consent must not be asked here")
        }
        fn approve_assert(&self, _rp_id: &str, _user_name: &str) -> bool {
            panic!("consent must not be asked here")
        }
        fn choose_account(&self, _rp_id: &str, _user_names: &[String]) -> Option<usize> {
            panic!("consent must not be asked here")
        }
    }

    fn run<F: std::future::Future>(f: F) -> F::Output {
        tokio::runtime::Runtime::new().unwrap().block_on(f)
    }

    fn with_unlocked_vault(name: &str) -> std::path::PathBuf {
        let mut path = std::env::temp_dir();
        path.push(format!("gabbro_ctap2_{name}.gabbro"));
        let pass = b"ctap2-test-pass";
        save_vault(&VaultBody::empty(), pass, &path).unwrap();
        run(unlock_vault(
            pass.to_vec(),
            path.to_str().unwrap().to_string(),
        ))
        .unwrap();
        path
    }

    fn cleanup(path: &std::path::Path) {
        let _ = lock_vault();
        let _ = std::fs::remove_file(path);
        let _ = std::fs::remove_file(format!("{}.bak", path.display()));
    }

    /// CBOR-encode a CTAP2 request: command byte + value.
    fn request(cmd: u8, v: &Value) -> Vec<u8> {
        let mut out = vec![cmd];
        ciborium::ser::into_writer(v, &mut out).unwrap();
        out
    }

    #[test]
    #[serial]
    fn describe_a_create_asks_with_the_site_and_account() {
        let path = with_unlocked_vault("desc_create");
        match describe_request(&request(0x01, &make_credential_value())) {
            RequestPlan::Ask {
                is_create,
                rp_id,
                accounts,
            } => {
                assert!(is_create);
                assert_eq!(rp_id, "example.com");
                assert_eq!(accounts, vec!["user@example.com".to_string()]);
            }
            RequestPlan::Respond(_) => panic!("a valid create must ask the user"),
        }
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn describe_an_assertion_lists_the_matching_accounts() {
        let path = with_unlocked_vault("desc_assert");
        let _ = handle_request(
            &request(0x01, &make_credential_value_named("a@example.com", b"h1")),
            &Approve,
        );
        let _ = handle_request(
            &request(0x01, &make_credential_value_named("b@example.com", b"h2")),
            &Approve,
        );
        match describe_request(&request(
            0x02,
            &get_assertion_value("example.com", &[0x22; 32]),
        )) {
            RequestPlan::Ask {
                is_create,
                accounts,
                ..
            } => {
                assert!(!is_create);
                assert_eq!(accounts.len(), 2, "both accounts offered");
            }
            RequestPlan::Respond(_) => panic!("matches must ask the user"),
        }
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn describe_responds_immediately_when_no_user_choice_applies() {
        // Locked, no-match, and garbage never reach a consent screen - the
        // daemon just sends these bytes back.
        let _ = lock_vault();
        let RequestPlan::Respond(locked) =
            describe_request(&request(0x01, &make_credential_value()))
        else {
            panic!("locked must respond, not ask")
        };
        assert_eq!(locked, vec![0x27], "OPERATION_DENIED");

        let path = with_unlocked_vault("desc_respond");
        let RequestPlan::Respond(nomatch) = describe_request(&request(
            0x02,
            &get_assertion_value("nobody.example", &[0x22; 32]),
        )) else {
            panic!("no match must respond, not ask")
        };
        assert_eq!(nomatch, vec![0x2e], "NO_CREDENTIALS");

        let RequestPlan::Respond(garbage) = describe_request(&[0x01, 0xff, 0xff]) else {
            panic!("garbage must respond, not ask")
        };
        assert_eq!(garbage, vec![0x12], "INVALID_CBOR");
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn perform_approved_create_matches_the_trait_path() {
        let path = with_unlocked_vault("perf_create");
        let resp = perform_approved(&request(0x01, &make_credential_value()), 0);
        assert_eq!(resp.first(), Some(&0x00), "CTAP2_OK");
        let stored = list_entry_summaries()
            .unwrap()
            .into_iter()
            .any(|s| s.entry_type == "Passkey");
        assert!(stored, "approved create stores the entry");
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn perform_approved_assert_signs_the_chosen_account() {
        use p256::ecdsa::signature::Verifier;
        let path = with_unlocked_vault("perf_assert");
        let make = handle_request(
            &request(
                0x01,
                &make_credential_value_named("only@example.com", b"h1"),
            ),
            &Approve,
        );
        let Value::Map(mmap) = ciborium::de::from_reader::<Value, _>(&make[1..]).unwrap() else {
            panic!("map")
        };
        let Value::Bytes(mad) = map_get(&mmap, 2) else {
            panic!("bytes")
        };
        let cose = mad[87..164].to_vec();

        let hash = [0x22u8; 32];
        let resp = perform_approved(
            &request(0x02, &get_assertion_value("example.com", &hash)),
            0,
        );
        assert_eq!(resp.first(), Some(&0x00), "CTAP2_OK");
        let Value::Map(map) = ciborium::de::from_reader::<Value, _>(&resp[1..]).unwrap() else {
            panic!("map")
        };
        let Value::Bytes(ad) = map_get(&map, 2) else {
            panic!("bytes")
        };
        let Value::Bytes(sig) = map_get(&map, 3) else {
            panic!("bytes")
        };
        let mut msg = ad.clone();
        msg.extend_from_slice(&hash);
        let vk = verifying_key_from_cose(&cose);
        let sig = p256::ecdsa::Signature::from_der(sig).unwrap();
        assert!(vk.verify(&msg, &sig).is_ok(), "the site accepts the login");
        cleanup(&path);
    }

    #[test]
    fn denied_response_is_the_operation_denied_status() {
        assert_eq!(denied_response(), vec![0x27]);
    }

    /// authenticatorMakeCredential request map (CTAP 2.1 section 6.1 keys).
    fn make_credential_value() -> Value {
        Value::Map(vec![
            (Value::Integer(1.into()), Value::Bytes(vec![0x11; 32])),
            (
                Value::Integer(2.into()),
                Value::Map(vec![
                    (Value::Text("id".into()), Value::Text("example.com".into())),
                    (Value::Text("name".into()), Value::Text("Example".into())),
                ]),
            ),
            (
                Value::Integer(3.into()),
                Value::Map(vec![
                    (
                        Value::Text("id".into()),
                        Value::Bytes(b"user-handle".to_vec()),
                    ),
                    (
                        Value::Text("name".into()),
                        Value::Text("user@example.com".into()),
                    ),
                    (
                        Value::Text("displayName".into()),
                        Value::Text("Sample User".into()),
                    ),
                ]),
            ),
            (
                Value::Integer(4.into()),
                Value::Array(vec![Value::Map(vec![
                    (Value::Text("type".into()), Value::Text("public-key".into())),
                    (Value::Text("alg".into()), Value::Integer((-7).into())),
                ])]),
            ),
        ])
    }

    /// Look up an integer key in a CBOR map.
    fn map_get(map: &[(Value, Value)], key: i128) -> &Value {
        map.iter()
            .find(|(k, _)| matches!(k, Value::Integer(i) if i128::from(*i) == key))
            .map(|(_, v)| v)
            .unwrap_or_else(|| panic!("key {key} missing"))
    }

    #[test]
    fn get_info_reports_a_passkey_capable_authenticator() {
        // authenticatorGetInfo (0x04), no request body.
        let resp = handle_request(&[0x04], &Approve);

        assert_eq!(resp.first(), Some(&0x00), "CTAP2_OK status");
        let v: Value = ciborium::de::from_reader(&resp[1..]).expect("CBOR body");
        let Value::Map(map) = v else {
            panic!("getInfo response is a CBOR map")
        };

        // 0x01 versions: both FIDO2 revisions, so old and new browsers engage.
        let Value::Array(versions) = map_get(&map, 1) else {
            panic!("versions is an array")
        };
        let names: Vec<&str> = versions.iter().filter_map(|v| v.as_text()).collect();
        assert!(names.contains(&"FIDO_2_0"), "got: {names:?}");
        assert!(names.contains(&"FIDO_2_1"), "got: {names:?}");

        // 0x03 aaguid: 16 zero bytes - none attestation, same as the core.
        let Value::Bytes(aaguid) = map_get(&map, 3) else {
            panic!("aaguid is bytes")
        };
        assert_eq!(aaguid.as_slice(), &[0u8; 16]);

        // 0x04 options: discoverable credentials + built-in user verification,
        // so browsers never demand a PIN.
        let Value::Map(options) = map_get(&map, 4) else {
            panic!("options is a map")
        };
        for opt in ["rk", "up", "uv"] {
            let set = options
                .iter()
                .any(|(k, v)| k.as_text() == Some(opt) && *v == Value::Bool(true));
            assert!(set, "option {opt} must be true");
        }

        // 0x05 maxMsgSize: matches libfido2's FIDO_MAXMSG default.
        assert_eq!(map_get(&map, 5), &Value::Integer(2048.into()));
    }

    #[test]
    #[serial]
    fn make_credential_with_consent_stores_entry_and_returns_attestation() {
        use sha2::{Digest, Sha256};
        let path = with_unlocked_vault("make");

        let resp = handle_request(&request(0x01, &make_credential_value()), &Approve);

        assert_eq!(resp.first(), Some(&0x00), "CTAP2_OK status");
        let v: Value = ciborium::de::from_reader(&resp[1..]).expect("CBOR body");
        let Value::Map(map) = v else {
            panic!("makeCredential response is a CBOR map")
        };
        // 0x01 fmt / 0x03 attStmt: none attestation, same as the Android path.
        assert_eq!(map_get(&map, 1), &Value::Text("none".into()));
        assert_eq!(map_get(&map, 3), &Value::Map(vec![]));
        // 0x02 authData: rpIdHash | flags 0x5d | zero counter | attested cred.
        let Value::Bytes(ad) = map_get(&map, 2) else {
            panic!("authData is bytes")
        };
        assert_eq!(&ad[..32], Sha256::digest(b"example.com").as_slice());
        assert_eq!(ad[32], 0x5d, "UP|UV|AT|BE|BS");
        assert_eq!(&ad[33..37], &[0, 0, 0, 0], "zero counter");

        // The credential is in the vault, listed like any entry.
        let stored = list_entry_summaries()
            .unwrap()
            .into_iter()
            .find(|s| s.entry_type == "Passkey")
            .expect("makeCredential must store a Passkey entry");
        assert_eq!(stored.title, "example.com");

        cleanup(&path);
    }

    #[test]
    #[serial]
    fn make_credential_denied_creates_nothing() {
        // Born green: item 10's implementation carries the denial branch.
        // Pinned so Cancel can never silently become a stored credential.
        let path = with_unlocked_vault("deny");

        let resp = handle_request(&request(0x01, &make_credential_value()), &Deny);

        assert_eq!(resp, vec![0x27], "CTAP2_ERR_OPERATION_DENIED, nothing else");
        let leaked = list_entry_summaries()
            .unwrap()
            .into_iter()
            .any(|s| s.entry_type == "Passkey");
        assert!(!leaked, "no entry may be created on Cancel");

        cleanup(&path);
    }

    #[test]
    #[serial]
    fn locked_vault_refuses_create_without_asking_consent() {
        // No unlock flow on Linux: locked = flat refusal, and the user is
        // never shown a consent screen for an operation that cannot happen.
        let _ = lock_vault();

        let resp = handle_request(&request(0x01, &make_credential_value()), &NeverAsked);

        assert_eq!(resp, vec![0x27], "CTAP2_ERR_OPERATION_DENIED, nothing else");
    }

    /// authenticatorGetAssertion request map (CTAP 2.1 section 6.2 keys).
    fn get_assertion_value(rp_id: &str, hash: &[u8]) -> Value {
        Value::Map(vec![
            (Value::Integer(1.into()), Value::Text(rp_id.into())),
            (Value::Integer(2.into()), Value::Bytes(hash.to_vec())),
        ])
    }

    /// A makeCredential request for a second account on the same site.
    fn make_credential_value_named(user_name: &str, handle: &[u8]) -> Value {
        let Value::Map(mut m) = make_credential_value() else {
            panic!("request is a map")
        };
        m[2].1 = Value::Map(vec![
            (Value::Text("id".into()), Value::Bytes(handle.to_vec())),
            (Value::Text("name".into()), Value::Text(user_name.into())),
        ]);
        Value::Map(m)
    }

    /// The credential id minted by a makeCredential response.
    fn minted_cred_id(resp: &[u8]) -> Vec<u8> {
        assert_eq!(resp.first(), Some(&0x00), "mint must succeed");
        let Value::Map(map) = ciborium::de::from_reader::<Value, _>(&resp[1..]).unwrap() else {
            panic!("makeCredential response is a map")
        };
        let Value::Bytes(ad) = map_get(&map, 2) else {
            panic!("authData is bytes")
        };
        ad[55..87].to_vec()
    }

    #[test]
    #[serial]
    fn allow_list_picks_the_site_named_credential() {
        // Two accounts on one site; the site names the second one. The
        // first-stored key must NOT answer - that would log the user into
        // the wrong account.
        let path = with_unlocked_vault("allowlist");
        let _ = minted_cred_id(&handle_request(
            &request(
                0x01,
                &make_credential_value_named("user1@example.com", b"h1"),
            ),
            &Approve,
        ));
        let cred_b = minted_cred_id(&handle_request(
            &request(
                0x01,
                &make_credential_value_named("user2@example.com", b"h2"),
            ),
            &Approve,
        ));

        let Value::Map(mut req) = get_assertion_value("example.com", &[0x22; 32]) else {
            panic!("request is a map")
        };
        req.push((
            Value::Integer(3.into()),
            Value::Array(vec![Value::Map(vec![
                (Value::Text("id".into()), Value::Bytes(cred_b.clone())),
                (Value::Text("type".into()), Value::Text("public-key".into())),
            ])]),
        ));
        let resp = handle_request(&request(0x02, &Value::Map(req)), &Approve);

        assert_eq!(resp.first(), Some(&0x00), "CTAP2_OK status");
        let Value::Map(map) = ciborium::de::from_reader::<Value, _>(&resp[1..]).unwrap() else {
            panic!("getAssertion response is a map")
        };
        let Value::Map(cred) = map_get(&map, 1) else {
            panic!("credential is a map")
        };
        let signed_with_b = cred.iter().any(|(k, v)| {
            k.as_text() == Some("id") && matches!(v, Value::Bytes(b) if *b == cred_b)
        });
        assert!(signed_with_b, "the site-named credential must answer");
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn empty_allow_list_with_several_accounts_asks_the_user_to_pick() {
        let path = with_unlocked_vault("chooser");
        let _ = minted_cred_id(&handle_request(
            &request(
                0x01,
                &make_credential_value_named("user1@example.com", b"h1"),
            ),
            &Approve,
        ));
        let cred_b = minted_cred_id(&handle_request(
            &request(
                0x01,
                &make_credential_value_named("user2@example.com", b"h2"),
            ),
            &Approve,
        ));

        /// Picks the second account; yes/no consent is off-limits here.
        struct PickSecond;
        impl Consent for PickSecond {
            fn approve_create(&self, _rp_id: &str, _user_name: &str) -> bool {
                panic!("not a create")
            }
            fn approve_assert(&self, _rp_id: &str, _user_name: &str) -> bool {
                panic!("several accounts need the chooser, not yes/no")
            }
            fn choose_account(&self, _rp_id: &str, users: &[String]) -> Option<usize> {
                users
                    .iter()
                    .position(|u| u == "user2@example.com")
                    .map(Some)
                    .expect("both accounts must be offered")
            }
        }
        let resp = handle_request(
            &request(0x02, &get_assertion_value("example.com", &[0x22; 32])),
            &PickSecond,
        );
        assert_eq!(resp.first(), Some(&0x00), "CTAP2_OK status");
        let Value::Map(map) = ciborium::de::from_reader::<Value, _>(&resp[1..]).unwrap() else {
            panic!("getAssertion response is a map")
        };
        let Value::Map(cred) = map_get(&map, 1) else {
            panic!("credential is a map")
        };
        let signed_with_b = cred.iter().any(|(k, v)| {
            k.as_text() == Some("id") && matches!(v, Value::Bytes(b) if *b == cred_b)
        });
        assert!(signed_with_b, "the picked account must answer");

        // Cancel in the picker refuses the whole operation.
        let resp = handle_request(
            &request(0x02, &get_assertion_value("example.com", &[0x22; 32])),
            &Deny,
        );
        assert_eq!(resp, vec![0x27], "CTAP2_ERR_OPERATION_DENIED on cancel");
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn allow_list_naming_an_absent_credential_says_no_credentials() {
        let path = with_unlocked_vault("allowlist_absent");
        let _ = handle_request(&request(0x01, &make_credential_value()), &Approve);

        let Value::Map(mut req) = get_assertion_value("example.com", &[0x22; 32]) else {
            panic!("request is a map")
        };
        req.push((
            Value::Integer(3.into()),
            Value::Array(vec![Value::Map(vec![
                (Value::Text("id".into()), Value::Bytes(vec![0xEE; 32])),
                (Value::Text("type".into()), Value::Text("public-key".into())),
            ])]),
        ));
        let resp = handle_request(&request(0x02, &Value::Map(req)), &NeverAsked);

        assert_eq!(resp, vec![0x2e], "CTAP2_ERR_NO_CREDENTIALS");
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn silent_up_false_allowlist_probe_answers_without_consent() {
        // Brave pre-flights a filled-username sign-in with an allowList
        // getAssertion carrying options.up=false (CTAP 2.1 silent
        // authentication). It must be answered with no consent and with UP
        // and UV clear - otherwise the user pays a second consent click for
        // every such sign-in (matrix D1 row 5b).
        let path = with_unlocked_vault("silent_probe");
        let cred = minted_cred_id(&handle_request(
            &request(
                0x01,
                &make_credential_value_named("user@example.com", b"h1"),
            ),
            &Approve,
        ));

        let Value::Map(mut req) = get_assertion_value("example.com", &[0x22; 32]) else {
            panic!("request is a map")
        };
        req.push((
            Value::Integer(3.into()),
            Value::Array(vec![Value::Map(vec![
                (Value::Text("id".into()), Value::Bytes(cred.clone())),
                (Value::Text("type".into()), Value::Text("public-key".into())),
            ])]),
        ));
        req.push((
            Value::Integer(5.into()),
            Value::Map(vec![(Value::Text("up".into()), Value::Bool(false))]),
        ));
        let resp = handle_request(&request(0x02, &Value::Map(req)), &NeverAsked);

        assert_eq!(resp.first(), Some(&0x00), "CTAP2_OK status");
        let Value::Map(map) = ciborium::de::from_reader::<Value, _>(&resp[1..]).unwrap() else {
            panic!("getAssertion response is a map")
        };
        let Value::Bytes(ad) = map_get(&map, 2) else {
            panic!("authData is bytes")
        };
        assert_eq!(ad[32] & 0x01, 0, "UP must be clear on a silent assertion");
        assert_eq!(ad[32] & 0x04, 0, "UV must be clear on a silent assertion");
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn silent_up_false_without_allowlist_refuses() {
        // Silent authentication is for allowList probes only: without one,
        // answering would hand any site a signed assertion for a discoverable
        // credential with zero user involvement. NO_CREDENTIALS, no consent.
        let path = with_unlocked_vault("silent_no_allowlist");
        let _ = handle_request(&request(0x01, &make_credential_value()), &Approve);

        let Value::Map(mut req) = get_assertion_value("example.com", &[0x22; 32]) else {
            panic!("request is a map")
        };
        req.push((
            Value::Integer(5.into()),
            Value::Map(vec![(Value::Text("up".into()), Value::Bool(false))]),
        ));
        let resp = handle_request(&request(0x02, &Value::Map(req)), &NeverAsked);

        assert_eq!(resp, vec![0x2e], "CTAP2_ERR_NO_CREDENTIALS");
        cleanup(&path);
    }

    /// Test-only COSE decoder: x||y from the pinned 77-byte layout.
    fn verifying_key_from_cose(cose: &[u8]) -> p256::ecdsa::VerifyingKey {
        let mut sec1 = vec![0x04u8];
        sec1.extend_from_slice(&cose[10..42]);
        sec1.extend_from_slice(&cose[45..77]);
        p256::ecdsa::VerifyingKey::from_sec1_bytes(&sec1).expect("COSE carries a valid point")
    }

    #[test]
    #[serial]
    fn get_assertion_with_consent_signs_the_challenge() {
        use p256::ecdsa::signature::Verifier;
        use sha2::{Digest, Sha256};
        let path = with_unlocked_vault("assert");

        // Mint the credential, then pull its id and public key from the
        // attested authData (credId at 55..87, COSE key at 87..164).
        let make_resp = handle_request(&request(0x01, &make_credential_value()), &Approve);
        let Value::Map(make_map) = ciborium::de::from_reader::<Value, _>(&make_resp[1..]).unwrap()
        else {
            panic!("makeCredential response is a map")
        };
        let Value::Bytes(make_ad) = map_get(&make_map, 2) else {
            panic!("authData is bytes")
        };
        let cred_id = make_ad[55..87].to_vec();
        let cose = &make_ad[87..164];

        let hash = vec![0x22u8; 32];
        let resp = handle_request(
            &request(0x02, &get_assertion_value("example.com", &hash)),
            &Approve,
        );

        assert_eq!(resp.first(), Some(&0x00), "CTAP2_OK status");
        let Value::Map(map) = ciborium::de::from_reader::<Value, _>(&resp[1..]).unwrap() else {
            panic!("getAssertion response is a map")
        };
        // 0x01 credential descriptor names the minted credential.
        let Value::Map(cred) = map_get(&map, 1) else {
            panic!("credential is a map")
        };
        let id_matches = cred.iter().any(|(k, v)| {
            k.as_text() == Some("id") && matches!(v, Value::Bytes(b) if *b == cred_id)
        });
        assert!(id_matches, "credential id must round-trip");
        // 0x02 authData: assertion flags, no attested-credential block.
        let Value::Bytes(ad) = map_get(&map, 2) else {
            panic!("authData is bytes")
        };
        assert_eq!(&ad[..32], Sha256::digest(b"example.com").as_slice());
        assert_eq!(ad[32], 0x1d, "UP|UV|BE|BS");
        // 0x03 signature: DER, verifies over authData || clientDataHash -
        // exactly what the site checks before accepting the login.
        let Value::Bytes(sig) = map_get(&map, 3) else {
            panic!("signature is bytes")
        };
        let vk = verifying_key_from_cose(cose);
        let mut msg = ad.clone();
        msg.extend_from_slice(&hash);
        let sig = p256::ecdsa::Signature::from_der(sig).expect("DER signature");
        assert!(vk.verify(&msg, &sig).is_ok(), "the site accepts the login");

        cleanup(&path);
    }

    #[test]
    #[serial]
    fn excluded_credential_is_reported_not_duplicated() {
        let path = with_unlocked_vault("exclude");
        let make_resp = handle_request(&request(0x01, &make_credential_value()), &Approve);
        let Value::Map(make_map) = ciborium::de::from_reader::<Value, _>(&make_resp[1..]).unwrap()
        else {
            panic!("makeCredential response is a map")
        };
        let Value::Bytes(make_ad) = map_get(&make_map, 2) else {
            panic!("authData is bytes")
        };
        let cred_id = make_ad[55..87].to_vec();

        // Same request again, now with an excludeList naming that credential
        // (key 5) - the site saying "not if the user already has this one".
        let Value::Map(mut req) = make_credential_value() else {
            panic!("request is a map")
        };
        req.push((
            Value::Integer(5.into()),
            Value::Array(vec![Value::Map(vec![
                (Value::Text("id".into()), Value::Bytes(cred_id)),
                (Value::Text("type".into()), Value::Text("public-key".into())),
            ])]),
        ));

        let resp = handle_request(&request(0x01, &Value::Map(req)), &Approve);

        assert_eq!(resp, vec![0x19], "CTAP2_ERR_CREDENTIAL_EXCLUDED");
        let count = list_entry_summaries()
            .unwrap()
            .into_iter()
            .filter(|s| s.entry_type == "Passkey")
            .count();
        assert_eq!(count, 1, "no duplicate stored");
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn assertion_without_a_matching_credential_says_no_credentials() {
        // Born green: an empty rp match already answers NO_CREDENTIALS.
        // Pinned with NeverAsked: the browser gets its "try another way"
        // screen and the user is never bothered for a site we hold nothing
        // for. A passkey for another site must not leak into the answer.
        let path = with_unlocked_vault("nomatch");
        let _ = handle_request(&request(0x01, &make_credential_value()), &Approve);

        let resp = handle_request(
            &request(0x02, &get_assertion_value("other.example", &[0x22; 32])),
            &NeverAsked,
        );

        assert_eq!(resp, vec![0x2e], "CTAP2_ERR_NO_CREDENTIALS");
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn malformed_cbor_gets_a_clean_error_never_a_crash() {
        // Born green: both command parsers already refuse bad CBOR. Pinned
        // because a panic here would kill the whole app, vault included.
        let path = with_unlocked_vault("garbage");

        let truncated = {
            let mut r = request(0x01, &make_credential_value());
            r.truncate(r.len() / 2);
            r
        };
        for bad in [
            vec![0x01, 0xff, 0xff, 0xff], // garbage bytes
            truncated,                    // valid CBOR cut mid-structure
            request(0x01, &Value::Text("not a map".into())),
            vec![0x02, 0xff, 0xff, 0xff],
            request(0x02, &Value::Integer(7.into())),
        ] {
            let resp = handle_request(&bad, &NeverAsked);
            assert_eq!(resp, vec![0x12], "CTAP2_ERR_INVALID_CBOR for {bad:?}");
        }
        let leaked = list_entry_summaries()
            .unwrap()
            .into_iter()
            .any(|s| s.entry_type == "Passkey");
        assert!(!leaked, "garbage must create nothing");
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn locked_vault_refuses_assert_without_asking_consent() {
        // Completes item 12: the assert side of the flat locked refusal.
        let _ = lock_vault();

        let resp = handle_request(
            &request(0x02, &get_assertion_value("example.com", &[0x22; 32])),
            &NeverAsked,
        );

        assert_eq!(resp, vec![0x27], "CTAP2_ERR_OPERATION_DENIED, nothing else");
    }
}
