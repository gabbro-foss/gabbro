//! Passkey provider bridge — the WebAuthn request/response layer.
//!
//! The Android Credential Manager (and later the Linux virtual authenticator)
//! hands over the relying party's request JSON verbatim; this module parses it,
//! drives the vault session and `crypto::webauthn`, and assembles the response
//! JSON the caller sends back. All parsing and crypto stay behind the bridge —
//! Kotlin passes strings through and never sees key material.

use base64::Engine;
use serde::Deserialize;

const ES256: i64 = -7;

/// A parsed WebAuthn registration request — only the fields Gabbro needs to
/// mint and store a credential.
#[derive(Debug)]
pub struct CreationRequest {
    pub rp_id: String,
    pub user_handle: Vec<u8>,
    pub user_name: String,
    pub user_display_name: String,
    pub challenge: Vec<u8>,
}

#[derive(Deserialize)]
struct RawRp {
    id: Option<String>,
}

#[derive(Deserialize)]
struct RawUser {
    id: String,
    name: String,
    #[serde(rename = "displayName", default)]
    display_name: String,
}

#[derive(Deserialize)]
struct RawParam {
    #[serde(rename = "type")]
    ty: String,
    alg: i64,
}

#[derive(Deserialize)]
struct RawCreationOptions {
    rp: RawRp,
    user: RawUser,
    challenge: String,
    #[serde(rename = "pubKeyCredParams")]
    pub_key_cred_params: Vec<RawParam>,
}

fn b64url(field: &str, s: &str) -> Result<Vec<u8>, String> {
    base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(s)
        .map_err(|_| format!("{field} is not valid base64url"))
}

/// Parse a W3C `PublicKeyCredentialCreationOptions` JSON string.
///
/// Strict on purpose: a missing rp.id or a parameter list without ES256 is a
/// refusal here, so the user never stores a credential that can't sign for the
/// site that requested it.
pub fn parse_creation_request(json: &str) -> Result<CreationRequest, String> {
    let raw: RawCreationOptions =
        serde_json::from_str(json).map_err(|e| format!("invalid creation request: {e}"))?;
    let rp_id = raw
        .rp
        .id
        .filter(|id| !id.is_empty())
        .ok_or("creation request carries no rp.id")?;
    if !raw
        .pub_key_cred_params
        .iter()
        .any(|p| p.ty == "public-key" && p.alg == ES256)
    {
        return Err(String::from(
            "relying party does not accept ES256, the only algorithm Gabbro provides",
        ));
    }
    Ok(CreationRequest {
        rp_id,
        user_handle: b64url("user.id", &raw.user.id)?,
        user_name: raw.user.name,
        user_display_name: raw.user.display_name,
        challenge: b64url("challenge", &raw.challenge)?,
    })
}

/// What Kotlin needs to assemble the registration response. Everything here is
/// public material — the private key stayed in the vault entry.
#[derive(Debug)]
pub struct RegistrationParts {
    pub credential_id: Vec<u8>,
    pub auth_data: Vec<u8>,
    pub public_key_cose: Vec<u8>,
}

/// Re-export: the CBOR attestation object wrapping an auth_data block.
pub use crate::crypto::webauthn::attestation_object;

/// Register a new passkey from a relying party's creation request: mint the
/// key pair, store the credential as a vault entry (persisted like any entry),
/// and return the public parts for the response. Fails when the vault is
/// locked — the caller shows the unlock flow and retries.
pub fn register_passkey(request_json: &str) -> Result<RegistrationParts, String> {
    use crate::crypto::webauthn;
    use crate::vault::entry::{EntryMeta, PasskeyEntry, VaultEntry};

    let req = parse_creation_request(request_json)?;
    let kp = webauthn::generate_es256();
    let credential_id = webauthn::new_credential_id();
    let private_key = kp.private_key.clone();
    let public_key_cose = kp.public_key_cose.clone();

    let now = crate::api::vault::chrono_now();
    let entry = VaultEntry::Passkey(PasskeyEntry {
        meta: EntryMeta {
            field_times: Default::default(),
            history: Vec::new(),
            id: crate::vault::entry::new_entry_id(),
            created_at: now.clone(),
            updated_at: now,
            folder: String::new(),
        },
        rp_id: req.rp_id.clone(),
        user_name: req.user_name,
        user_display_name: req.user_display_name,
        user_handle: req.user_handle,
        credential_id: credential_id.clone(),
        private_key,
        public_key_cose: public_key_cose.clone(),
        algorithm: -7,
        notes: None,
        custom_fields: vec![],
    });
    crate::vault::session::session_create_entry(entry)?;

    let auth_data =
        webauthn::registration_authenticator_data(&req.rp_id, &credential_id, &public_key_cose);
    Ok(RegistrationParts {
        credential_id,
        auth_data,
        public_key_cose,
    })
}

/// A parsed WebAuthn sign-in request.
#[derive(Debug)]
pub struct AssertionRequest {
    pub rp_id: String,
    pub challenge: Vec<u8>,
    /// Credential ids the relying party will accept; empty = any discoverable
    /// credential for the rp.
    pub allow_credential_ids: Vec<Vec<u8>>,
}

#[derive(Deserialize)]
struct RawDescriptor {
    #[serde(rename = "type")]
    ty: String,
    id: String,
}

#[derive(Deserialize)]
struct RawRequestOptions {
    challenge: String,
    #[serde(rename = "rpId")]
    rp_id: Option<String>,
    #[serde(rename = "allowCredentials", default)]
    allow_credentials: Vec<RawDescriptor>,
}

/// Parse a W3C `PublicKeyCredentialRequestOptions` JSON string. A missing rpId
/// is refused: without it there is nothing safe to match credentials against.
pub fn parse_assertion_request(json: &str) -> Result<AssertionRequest, String> {
    let raw: RawRequestOptions =
        serde_json::from_str(json).map_err(|e| format!("invalid assertion request: {e}"))?;
    let rp_id = raw
        .rp_id
        .filter(|id| !id.is_empty())
        .ok_or("assertion request carries no rpId")?;
    let mut allow = Vec::new();
    for d in raw.allow_credentials {
        if d.ty == "public-key" {
            allow.push(b64url("allowCredentials.id", &d.id)?);
        }
    }
    Ok(AssertionRequest {
        rp_id,
        challenge: b64url("challenge", &raw.challenge)?,
        allow_credential_ids: allow,
    })
}

/// One selectable credential for the caller's account picker. No key material.
#[derive(Debug)]
pub struct PasskeyMatchData {
    pub entry_id: String,
    pub rp_id: String,
    pub user_name: String,
    pub user_display_name: String,
    pub credential_id: Vec<u8>,
}

/// The vault's credentials answering a sign-in request: exact rp_id match only
/// (a passkey for example.com must never answer a lookalike), narrowed by the
/// relying party's allow-list when it names specific credentials.
pub fn passkeys_for_request(request_json: &str) -> Result<Vec<PasskeyMatchData>, String> {
    let req = parse_assertion_request(request_json)?;
    let entries = crate::vault::session::session_passkeys_for_rp(&req.rp_id)?;
    Ok(entries
        .into_iter()
        .filter(|e| {
            req.allow_credential_ids.is_empty()
                || req.allow_credential_ids.contains(&e.credential_id)
        })
        .map(|e| PasskeyMatchData {
            entry_id: e.meta.id.clone(),
            rp_id: e.rp_id.clone(),
            user_name: e.user_name.clone(),
            user_display_name: e.user_display_name.clone(),
            credential_id: e.credential_id.clone(),
        })
        .collect())
}

/// What Kotlin needs to assemble the sign-in response.
#[derive(Debug)]
pub struct AssertionParts {
    pub credential_id: Vec<u8>,
    pub auth_data: Vec<u8>,
    pub signature_der: Vec<u8>,
    pub user_handle: Vec<u8>,
}

/// Sign a relying party's challenge with the chosen credential. The private
/// key is read from the session and never leaves this function.
pub fn sign_passkey_assertion(
    entry_id: &str,
    client_data_hash: &[u8],
) -> Result<AssertionParts, String> {
    use crate::crypto::webauthn;
    let entry = crate::vault::session::get_entry(entry_id)?;
    let e = match &entry {
        crate::vault::entry::VaultEntry::Passkey(e) => e,
        _ => return Err(String::from("entry is not a passkey")),
    };
    let auth_data = webauthn::assertion_authenticator_data(&e.rp_id);
    let signature_der = webauthn::sign_assertion(&e.private_key, &auth_data, client_data_hash)
        .map_err(|err| err.to_string())?;
    Ok(AssertionParts {
        credential_id: e.credential_id.clone(),
        auth_data,
        signature_der,
        user_handle: e.user_handle.clone(),
    })
}

fn b64url_encode(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

/// Placeholder `clientDataJSON` (b64url of `{}`) for the privileged-browser
/// path: the browser substitutes its own client data, but strict W3C response
/// parsers require the member to exist.
fn placeholder_client_data() -> String {
    b64url_encode(b"{}")
}

/// SubjectPublicKeyInfo DER wrapping the ES256 key from our pinned 77-byte
/// COSE layout (x at 10..42, y at 45..77) — the `response.publicKey` easy
/// accessor. Constant P-256 prefix, no ASN.1 dependency.
fn spki_from_cose(cose: &[u8]) -> Vec<u8> {
    const P256_SPKI_PREFIX: [u8; 26] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08,
        0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ];
    let mut out = Vec::with_capacity(91);
    out.extend_from_slice(&P256_SPKI_PREFIX);
    out.push(0x04);
    out.extend_from_slice(&cose[10..42]);
    out.extend_from_slice(&cose[45..77]);
    out
}

/// Register a passkey and return the complete W3C `RegistrationResponseJSON`
/// the caller sends back verbatim. `client_data_json_b64url` is included when
/// the provider built the client data itself (native-app flow); privileged
/// browsers supply their own and pass `None`.
pub fn registration_response_json(
    request_json: &str,
    client_data_json_b64url: Option<String>,
) -> Result<String, String> {
    let parts = register_passkey(request_json)?;
    let id = b64url_encode(&parts.credential_id);
    // Every member the W3C RegistrationResponseJSON shape requires — browsers
    // parse this strictly, and a missing member fails the whole ceremony.
    let response = serde_json::json!({
        "clientDataJSON": client_data_json_b64url.unwrap_or_else(placeholder_client_data),
        "attestationObject": b64url_encode(&attestation_object(&parts.auth_data)),
        "authenticatorData": b64url_encode(&parts.auth_data),
        "publicKey": b64url_encode(&spki_from_cose(&parts.public_key_cose)),
        "publicKeyAlgorithm": ES256,
        "transports": ["internal", "hybrid"],
    });
    let v = serde_json::json!({
        "id": id,
        "rawId": id,
        "type": "public-key",
        "authenticatorAttachment": "platform",
        "response": response,
        "clientExtensionResults": {},
    });
    serde_json::to_string(&v).map_err(|e| e.to_string())
}

/// Sign and return the complete W3C `AuthenticationResponseJSON`.
///
/// Exactly one client-data source: the provider-built clientDataJSON (native
/// apps — we hash it ourselves and include it), or the caller's pre-computed
/// hash (privileged browsers — they attach their own clientDataJSON).
pub fn assertion_response_json(
    entry_id: &str,
    client_data_json_b64url: Option<String>,
    client_data_hash_b64url: Option<String>,
) -> Result<String, String> {
    use sha2::{Digest, Sha256};
    let (hash, cdj_member) = match (client_data_json_b64url, client_data_hash_b64url) {
        (Some(cdj), None) => {
            let raw = b64url("clientDataJSON", &cdj)?;
            (Sha256::digest(&raw).to_vec(), cdj)
        }
        // Privileged caller: it substitutes its own clientDataJSON, but the
        // member must exist for strict parsers — placeholder, never absent.
        (None, Some(h)) => (b64url("clientDataHash", &h)?, placeholder_client_data()),
        _ => {
            return Err(String::from(
                "exactly one of clientDataJSON or clientDataHash is required",
            ))
        }
    };
    let parts = sign_passkey_assertion(entry_id, &hash)?;
    let id = b64url_encode(&parts.credential_id);
    let response = serde_json::json!({
        "clientDataJSON": cdj_member,
        "authenticatorData": b64url_encode(&parts.auth_data),
        "signature": b64url_encode(&parts.signature_der),
        "userHandle": b64url_encode(&parts.user_handle),
    });
    let v = serde_json::json!({
        "id": id,
        "rawId": id,
        "type": "public-key",
        "authenticatorAttachment": "platform",
        "response": response,
        "clientExtensionResults": {},
    });
    serde_json::to_string(&v).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    // W3C PublicKeyCredentialCreationOptions JSON, as a browser sends it.
    fn creation_json() -> String {
        String::from(
            r#"{
            "rp": {"id": "example.com", "name": "Example"},
            "user": {"id": "dXNlci1oYW5kbGU", "name": "user@example.com", "displayName": "Sample User"},
            "challenge": "Y2hhbGxlbmdlLWJ5dGVz",
            "pubKeyCredParams": [
                {"type": "public-key", "alg": -8},
                {"type": "public-key", "alg": -7},
                {"type": "public-key", "alg": -257}
            ]
        }"#,
        )
    }

    #[test]
    fn creation_request_parses_the_fields_we_register_with() {
        let req = parse_creation_request(&creation_json()).unwrap();
        assert_eq!(req.rp_id, "example.com");
        assert_eq!(req.user_name, "user@example.com");
        assert_eq!(req.user_display_name, "Sample User");
        assert_eq!(req.user_handle, b"user-handle");
        assert_eq!(req.challenge, b"challenge-bytes");
    }

    #[test]
    fn creation_request_without_es256_is_refused() {
        // A site that only accepts algorithms we cannot provide must get a
        // clean refusal, not a credential that can never sign.
        let json = creation_json().replace("-7", "-257");
        let err = parse_creation_request(&json).unwrap_err();
        assert!(err.contains("ES256"), "got: {err}");
    }

    #[test]
    fn creation_request_with_missing_rp_id_is_refused() {
        let json = creation_json().replace(r#""id": "example.com", "#, "");
        assert!(parse_creation_request(&json).is_err());
    }

    #[test]
    fn creation_request_with_invalid_json_is_refused() {
        assert!(parse_creation_request("not json").is_err());
    }

    #[test]
    fn creation_request_with_malformed_base64url_is_refused() {
        let json = creation_json().replace("Y2hhbGxlbmdlLWJ5dGVz", "!!!not-b64url!!!");
        assert!(parse_creation_request(&json).is_err());
    }

    // ── Registration against a live session ──────────────────────────────────

    use crate::api::vault::save_vault;
    use crate::api::vault_bridge::{list_entry_summaries, lock_vault, unlock_vault};
    use crate::vault::serialization::VaultBody;
    use serial_test::serial;

    fn run<F: std::future::Future>(f: F) -> F::Output {
        tokio::runtime::Runtime::new().unwrap().block_on(f)
    }

    fn with_unlocked_vault(name: &str) -> std::path::PathBuf {
        let mut path = std::env::temp_dir();
        path.push(format!("gabbro_passkey_bridge_{name}.gabbro"));
        let pass = b"passkey-bridge-pass";
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

    #[test]
    #[serial]
    fn register_passkey_stores_the_entry_and_returns_attestation_parts() {
        use sha2::{Digest, Sha256};
        let path = with_unlocked_vault("register");

        let parts = register_passkey(&creation_json()).unwrap();

        // The credential is in the vault, listed like any entry.
        let stored = list_entry_summaries()
            .unwrap()
            .into_iter()
            .find(|s| s.entry_type == "Passkey")
            .expect("registration must store a Passkey entry");
        assert_eq!(stored.title, "example.com");

        // Attested authenticatorData layout, byte-pinned:
        // rpIdHash(32) | flags(1) | counter(4) | AAGUID(16) | credIdLen(2) |
        // credId | COSE key. Flags 0x5d = UP|UV|AT|BE|BS.
        let ad = &parts.auth_data;
        assert_eq!(&ad[..32], Sha256::digest(b"example.com").as_slice());
        assert_eq!(ad[32], 0x5d);
        assert_eq!(&ad[33..37], &[0, 0, 0, 0]);
        assert_eq!(&ad[37..53], &[0u8; 16], "AAGUID is zero (none attestation)");
        let len = u16::from_be_bytes([ad[53], ad[54]]) as usize;
        assert_eq!(len, 32);
        assert_eq!(&ad[55..55 + len], parts.credential_id.as_slice());
        assert_eq!(ad[55 + len..].len(), 77, "COSE key closes the structure");

        // The attestation object wraps that auth_data: CBOR
        // {"fmt": "none", "attStmt": {}, "authData": <bytes>}.
        let att = attestation_object(&parts.auth_data);
        assert!(
            att.starts_with(&[0xa3, 0x63, b'f', b'm', b't', 0x64, b'n', b'o', b'n', b'e']),
            "attestation format must be none"
        );
        assert!(
            att.windows(ad.len()).any(|w| w == &ad[..]),
            "authData must be embedded verbatim"
        );

        cleanup(&path);
    }

    #[test]
    #[serial]
    fn register_passkey_with_locked_vault_says_locked() {
        let _ = lock_vault();
        let err = register_passkey(&creation_json()).unwrap_err();
        assert!(err.contains("locked"), "got: {err}");
    }

    // ── Assertion (sign-in) ──────────────────────────────────────────────────

    fn assertion_json(rp_id: &str) -> String {
        format!(
            r#"{{"challenge": "Y2hhbGxlbmdlLWJ5dGVz", "rpId": "{rp_id}", "allowCredentials": []}}"#
        )
    }

    #[test]
    fn assertion_request_parses_rp_and_challenge() {
        let req = parse_assertion_request(&assertion_json("example.com")).unwrap();
        assert_eq!(req.rp_id, "example.com");
        assert_eq!(req.challenge, b"challenge-bytes");
        assert!(req.allow_credential_ids.is_empty());
    }

    #[test]
    fn assertion_request_without_rp_id_is_refused() {
        assert!(parse_assertion_request(r#"{"challenge": "YWJj"}"#).is_err());
    }

    #[test]
    #[serial]
    fn assertion_finds_only_exact_rp_matches_and_signs() {
        use p256::ecdsa::signature::Verifier;
        use sha2::{Digest, Sha256};
        let path = with_unlocked_vault("assert");
        register_passkey(&creation_json()).unwrap();

        // Exact match: one hit, carrying what the account picker shows.
        let matches = passkeys_for_request(&assertion_json("example.com")).unwrap();
        assert_eq!(matches.len(), 1);
        assert_eq!(matches[0].user_name, "user@example.com");

        // R6: lookalikes and subdomains match nothing — a passkey for
        // example.com must never answer for anyone else.
        assert!(passkeys_for_request(&assertion_json("app.example.com"))
            .unwrap()
            .is_empty());
        assert!(
            passkeys_for_request(&assertion_json("example.com.evil.test"))
                .unwrap()
                .is_empty()
        );

        // Signing: verifies against the registered public key over exactly
        // authenticatorData || clientDataHash.
        let hash = [0x42u8; 32];
        let parts = sign_passkey_assertion(&matches[0].entry_id, &hash).unwrap();
        assert_eq!(
            &parts.auth_data[..32],
            Sha256::digest(b"example.com").as_slice()
        );
        assert_eq!(
            parts.auth_data[32], 0x1d,
            "UP|UV|BE|BS, no AT on assertions"
        );
        assert_eq!(parts.user_handle, b"user-handle");
        assert_eq!(parts.credential_id, matches[0].credential_id);

        let cose = &register_cose_of(&matches[0].entry_id);
        let vk = verifying_key_from_cose(cose);
        let mut msg = parts.auth_data.clone();
        msg.extend_from_slice(&hash);
        let sig = p256::ecdsa::Signature::from_der(&parts.signature_der).unwrap();
        assert!(vk.verify(&msg, &sig).is_ok());

        cleanup(&path);
    }

    #[test]
    #[serial]
    fn assertion_honours_the_allow_list() {
        let path = with_unlocked_vault("allowlist");
        register_passkey(&creation_json()).unwrap();
        let all = passkeys_for_request(&assertion_json("example.com")).unwrap();

        // An allow-list naming a different credential filters ours out...
        let other = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode([0xEEu8; 32]);
        let json = format!(
            r#"{{"challenge": "YWJj", "rpId": "example.com", "allowCredentials": [{{"type": "public-key", "id": "{other}"}}]}}"#
        );
        assert!(passkeys_for_request(&json).unwrap().is_empty());

        // ...and one naming ours keeps it.
        let ours = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&all[0].credential_id);
        let json = format!(
            r#"{{"challenge": "YWJj", "rpId": "example.com", "allowCredentials": [{{"type": "public-key", "id": "{ours}"}}]}}"#
        );
        assert_eq!(passkeys_for_request(&json).unwrap().len(), 1);

        cleanup(&path);
    }

    #[test]
    #[serial]
    fn assertion_with_locked_vault_says_locked() {
        let _ = lock_vault();
        let err = passkeys_for_request(&assertion_json("example.com")).unwrap_err();
        assert!(err.contains("locked"), "got: {err}");
    }

    // ── Full W3C response JSON (what Kotlin relays verbatim) ─────────────────

    #[test]
    #[serial]
    fn registration_response_json_matches_the_w3c_shape() {
        let path = with_unlocked_vault("reg_response");
        let cdj_raw =
            br#"{"type":"webauthn.create","challenge":"Y2hhbGxlbmdlLWJ5dGVz","origin":"https://example.com"}"#;
        let cdj = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(cdj_raw);

        let resp = registration_response_json(&creation_json(), Some(cdj.clone())).unwrap();
        let v: serde_json::Value = serde_json::from_str(&resp).unwrap();

        assert_eq!(v["type"], "public-key");
        assert_eq!(v["authenticatorAttachment"], "platform");
        assert_eq!(v["id"], v["rawId"]);
        let raw_id = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(v["rawId"].as_str().unwrap())
            .expect("rawId is base64url");
        assert_eq!(raw_id.len(), 32);
        assert_eq!(v["response"]["clientDataJSON"], cdj.as_str());
        let att = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(v["response"]["attestationObject"].as_str().unwrap())
            .expect("attestationObject is base64url");
        assert!(att.starts_with(&[0xa3, 0x63, b'f', b'm', b't', 0x64, b'n', b'o', b'n', b'e']));
        let transports: Vec<&str> = v["response"]["transports"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t.as_str().unwrap())
            .collect();
        assert!(transports.contains(&"internal") && transports.contains(&"hybrid"));
        assert!(v["clientExtensionResults"].as_object().unwrap().is_empty());

        cleanup(&path);
    }

    #[test]
    #[serial]
    fn assertion_response_json_signature_verifies_over_client_data() {
        use p256::ecdsa::signature::Verifier;
        use sha2::{Digest, Sha256};
        let path = with_unlocked_vault("assert_response");
        register_passkey(&creation_json()).unwrap();
        let matches = passkeys_for_request(&assertion_json("example.com")).unwrap();

        let cdj_raw =
            br#"{"type":"webauthn.get","challenge":"Y2hhbGxlbmdlLWJ5dGVz","origin":"https://example.com"}"#;
        let cdj = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(cdj_raw);

        let resp = assertion_response_json(&matches[0].entry_id, Some(cdj.clone()), None).unwrap();
        let v: serde_json::Value = serde_json::from_str(&resp).unwrap();

        assert_eq!(v["type"], "public-key");
        assert_eq!(v["response"]["clientDataJSON"], cdj.as_str());
        assert_eq!(
            v["response"]["userHandle"],
            base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(b"user-handle")
        );

        let b64 = &base64::engine::general_purpose::URL_SAFE_NO_PAD;
        let auth_data = b64
            .decode(v["response"]["authenticatorData"].as_str().unwrap())
            .unwrap();
        let sig_der = b64
            .decode(v["response"]["signature"].as_str().unwrap())
            .unwrap();
        let mut msg = auth_data.clone();
        msg.extend_from_slice(&Sha256::digest(cdj_raw));
        let vk = verifying_key_from_cose(&register_cose_of(&matches[0].entry_id));
        let sig = p256::ecdsa::Signature::from_der(&sig_der).unwrap();
        assert!(vk.verify(&msg, &sig).is_ok());

        cleanup(&path);
    }

    #[test]
    #[serial]
    fn assertion_response_with_caller_hash_uses_placeholder_client_data() {
        // Privileged browsers hand us a pre-computed hash and substitute their
        // own clientDataJSON — but the field must still be present as a
        // placeholder, or the browser's strict JSON parse fails (Android
        // credential-provider docs; S23 "unknown error").
        let path = with_unlocked_vault("assert_hash");
        register_passkey(&creation_json()).unwrap();
        let matches = passkeys_for_request(&assertion_json("example.com")).unwrap();
        let hash = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode([0x42u8; 32]);

        let resp = assertion_response_json(&matches[0].entry_id, None, Some(hash.clone())).unwrap();
        let v: serde_json::Value = serde_json::from_str(&resp).unwrap();
        assert_eq!(v["response"]["clientDataJSON"], "e30", "b64url of '{{}}'");
        assert!(v["response"]["signature"].as_str().is_some());

        // Exactly one client-data source is required.
        assert!(assertion_response_json(&matches[0].entry_id, None, None).is_err());

        cleanup(&path);
    }

    #[test]
    #[serial]
    fn registration_response_json_carries_the_easy_accessors() {
        // Browsers parse RegistrationResponseJSON strictly: authenticatorData,
        // publicKey and publicKeyAlgorithm are required members. Brave on the
        // S23 rejected a response without them ("unknown error" on the site).
        let path = with_unlocked_vault("reg_accessors");
        let resp = registration_response_json(&creation_json(), None).unwrap();
        let v: serde_json::Value = serde_json::from_str(&resp).unwrap();
        let b64 = &base64::engine::general_purpose::URL_SAFE_NO_PAD;

        let auth_data = b64
            .decode(v["response"]["authenticatorData"].as_str().unwrap())
            .unwrap();
        let att = b64
            .decode(v["response"]["attestationObject"].as_str().unwrap())
            .unwrap();
        assert!(
            att.windows(auth_data.len()).any(|w| w == &auth_data[..]),
            "authenticatorData must be the attestationObject's embedded auth data"
        );

        assert_eq!(v["response"]["publicKeyAlgorithm"], -7);
        let spki = b64
            .decode(v["response"]["publicKey"].as_str().unwrap())
            .unwrap();
        assert_eq!(spki.len(), 91, "P-256 SubjectPublicKeyInfo DER");
        // The SPKI wraps the same uncompressed point the COSE key carries
        // (pinned 77-byte layout closing the auth data).
        let cose = &auth_data[auth_data.len() - 77..];
        assert_eq!(spki[26], 0x04);
        assert_eq!(&spki[27..59], &cose[10..42]);
        assert_eq!(&spki[59..91], &cose[45..77]);

        cleanup(&path);
    }

    #[test]
    #[serial]
    fn registration_response_without_client_data_uses_placeholder() {
        // Privileged-browser path: the field must exist as a placeholder, not
        // be absent (the browser replaces it with its own client data).
        let path = with_unlocked_vault("reg_placeholder");
        let resp = registration_response_json(&creation_json(), None).unwrap();
        let v: serde_json::Value = serde_json::from_str(&resp).unwrap();
        assert_eq!(v["response"]["clientDataJSON"], "e30", "b64url of '{{}}'");
        cleanup(&path);
    }

    /// Fetch the stored COSE public key of an entry via the bridge DTO's b64
    /// credential id sibling — test-only, through get_entry.
    fn register_cose_of(entry_id: &str) -> Vec<u8> {
        match &crate::vault::session::get_entry(entry_id).unwrap() {
            crate::vault::entry::VaultEntry::Passkey(e) => e.public_key_cose.clone(),
            _ => panic!("expected passkey"),
        }
    }

    /// Test-only COSE decoder (pinned 77-byte layout).
    fn verifying_key_from_cose(cose: &[u8]) -> p256::ecdsa::VerifyingKey {
        let mut sec1 = vec![0x04u8];
        sec1.extend_from_slice(&cose[10..42]);
        sec1.extend_from_slice(&cose[45..77]);
        p256::ecdsa::VerifyingKey::from_sec1_bytes(&sec1).expect("valid point")
    }
}

/// JNI surface for GabbroCredentialProviderService — same pattern as
/// `autofill_bridge::jni`: Kotlin passes JSON strings through, errors come back
/// as `{"error": "..."}` (check for the "error" key before using a result).
#[cfg(target_os = "android")]
pub mod jni_glue {
    use jni::objects::{JClass, JString};
    use jni::JNIEnv;

    fn error_json(msg: &str) -> String {
        serde_json::json!({ "error": msg }).to_string()
    }

    fn get_string(env: &mut JNIEnv, s: &JString) -> Option<String> {
        env.get_string(s).ok().map(Into::into)
    }

    fn reply<'local>(env: &JNIEnv<'local>, s: String) -> JString<'local> {
        env.new_string(&s).unwrap_or_else(|_| {
            env.new_string("{\"error\":\"jni allocation failed\"}")
                .expect("failed to allocate fallback JString")
        })
    }

    /// `{"matches": [{"entryId", "rpId", "userName", "userDisplayName",
    /// "credentialIdB64"}]}` or `{"error": "..."}` (locked vault included).
    #[no_mangle]
    pub extern "system" fn Java_app_gabbro_gabbro_RustBridge_passkeysForRequest<'local>(
        mut env: JNIEnv<'local>,
        _class: JClass<'local>,
        request_json: JString<'local>,
    ) -> JString<'local> {
        let Some(req) = get_string(&mut env, &request_json) else {
            return reply(&env, error_json("bad request string"));
        };
        let out = match super::passkeys_for_request(&req) {
            Ok(matches) => {
                let items: Vec<serde_json::Value> = matches
                    .iter()
                    .map(|m| {
                        serde_json::json!({
                            "entryId": m.entry_id,
                            "rpId": m.rp_id,
                            "userName": m.user_name,
                            "userDisplayName": m.user_display_name,
                            "credentialIdB64": super::b64url_encode(&m.credential_id),
                        })
                    })
                    .collect();
                serde_json::json!({ "matches": items }).to_string()
            }
            Err(e) => error_json(&e),
        };
        reply(&env, out)
    }

    /// The W3C RegistrationResponseJSON, or `{"error": "..."}`. Pass the
    /// provider-built clientDataJSON (base64url) or null for privileged callers.
    #[no_mangle]
    pub extern "system" fn Java_app_gabbro_gabbro_RustBridge_registerPasskey<'local>(
        mut env: JNIEnv<'local>,
        _class: JClass<'local>,
        request_json: JString<'local>,
        client_data_json_b64: JString<'local>,
    ) -> JString<'local> {
        let Some(req) = get_string(&mut env, &request_json) else {
            return reply(&env, error_json("bad request string"));
        };
        let cdj = get_string(&mut env, &client_data_json_b64);
        let out = super::registration_response_json(&req, cdj).unwrap_or_else(|e| error_json(&e));
        reply(&env, out)
    }

    /// The W3C AuthenticationResponseJSON, or `{"error": "..."}`. Exactly one
    /// of clientDataJSON / clientDataHash (both base64url, other null).
    #[no_mangle]
    pub extern "system" fn Java_app_gabbro_gabbro_RustBridge_signPasskeyAssertion<'local>(
        mut env: JNIEnv<'local>,
        _class: JClass<'local>,
        entry_id: JString<'local>,
        client_data_json_b64: JString<'local>,
        client_data_hash_b64: JString<'local>,
    ) -> JString<'local> {
        let Some(id) = get_string(&mut env, &entry_id) else {
            return reply(&env, error_json("bad entry id string"));
        };
        let cdj = get_string(&mut env, &client_data_json_b64);
        let hash = get_string(&mut env, &client_data_hash_b64);
        let out = super::assertion_response_json(&id, cdj, hash).unwrap_or_else(|e| error_json(&e));
        reply(&env, out)
    }
}
