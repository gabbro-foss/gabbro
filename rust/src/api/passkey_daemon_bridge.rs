//! Bridge surface for the Linux passkey daemon (ADR-009).
//!
//! The Dart daemon pumps the uhid device and reassembles CTAPHID messages,
//! then drives each CTAP2 request across this seam: `passkey_plan` says
//! whether to ask the user or reply immediately; `passkey_perform` runs the
//! approved request; `passkey_denied` is the cancel response. The private key
//! never crosses the bridge — only these opaque CTAP2 response bytes do.

#[cfg(target_os = "linux")]
use crate::ctap2::{self, RequestPlan};
#[cfg(target_os = "linux")]
use crate::frb_generated::StreamSink;

/// What the daemon should do with one CTAP2 request. When `immediate_response`
/// is set the daemon frames those bytes straight back (getInfo, locked vault,
/// no match, malformed); otherwise it shows the consent dialog for `rp_id`,
/// offering `accounts`, then calls `passkey_perform` with the chosen index.
pub struct PasskeyPlan {
    pub immediate_response: Option<Vec<u8>>,
    pub is_create: bool,
    pub rp_id: String,
    pub accounts: Vec<String>,
}

/// Describe one reassembled CTAP2 request (command byte + CBOR): no crypto,
/// no signing.
#[cfg(target_os = "linux")]
pub fn passkey_plan(payload: Vec<u8>) -> PasskeyPlan {
    match ctap2::describe_request(&payload) {
        RequestPlan::Respond(bytes) => PasskeyPlan {
            immediate_response: Some(bytes),
            is_create: false,
            rp_id: String::new(),
            accounts: Vec::new(),
        },
        RequestPlan::Ask {
            is_create,
            rp_id,
            accounts,
        } => PasskeyPlan {
            immediate_response: None,
            is_create,
            rp_id,
            accounts,
        },
    }
}

/// Perform a user-approved request; `account_index` selects among the accounts
/// `passkey_plan` listed (ignored for a create).
#[cfg(target_os = "linux")]
pub fn passkey_perform(payload: Vec<u8>, account_index: usize) -> Vec<u8> {
    ctap2::perform_approved(&payload, account_index)
}

/// The response to frame back when the user cancels at the consent dialog.
#[cfg(target_os = "linux")]
pub fn passkey_denied() -> Vec<u8> {
    ctap2::denied_response()
}

/// Start the Linux passkey daemon: create the uhid device and stream each
/// complete CTAP2 request (command byte + CBOR) to Dart. Rust keeps the
/// request alive with KEEPALIVE until `passkey_daemon_respond`.
#[cfg(target_os = "linux")]
pub fn passkey_daemon_start(sink: StreamSink<Vec<u8>>) -> Result<(), String> {
    crate::passkey_daemon::start(move |payload| {
        let _ = sink.add(payload);
    })
}

/// Hand a finished CTAP2 response (or the denied bytes) back to the daemon.
#[cfg(target_os = "linux")]
pub fn passkey_daemon_respond(response: Vec<u8>) -> Result<(), String> {
    crate::passkey_daemon::respond(response)
}

/// Stop the daemon and unplug the virtual device.
#[cfg(target_os = "linux")]
pub fn passkey_daemon_stop() {
    crate::passkey_daemon::stop()
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;
    use crate::api::vault::save_vault;
    use crate::api::vault_bridge::{lock_vault, unlock_vault};
    use crate::vault::serialization::VaultBody;
    use ciborium::value::Value;
    use serial_test::serial;

    fn run<F: std::future::Future>(f: F) -> F::Output {
        tokio::runtime::Runtime::new().unwrap().block_on(f)
    }

    fn with_unlocked_vault(name: &str) -> std::path::PathBuf {
        let mut path = std::env::temp_dir();
        path.push(format!("gabbro_daemon_{name}.gabbro"));
        let pass = b"daemon-test-pass";
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

    fn request(cmd: u8, v: &Value) -> Vec<u8> {
        let mut out = vec![cmd];
        ciborium::ser::into_writer(v, &mut out).unwrap();
        out
    }

    fn create_value() -> Value {
        Value::Map(vec![
            (Value::Integer(1.into()), Value::Bytes(vec![0x11; 32])),
            (
                Value::Integer(2.into()),
                Value::Map(vec![(
                    Value::Text("id".into()),
                    Value::Text("example.com".into()),
                )]),
            ),
            (
                Value::Integer(3.into()),
                Value::Map(vec![
                    (Value::Text("id".into()), Value::Bytes(b"h1".to_vec())),
                    (
                        Value::Text("name".into()),
                        Value::Text("user@example.com".into()),
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

    #[test]
    #[serial]
    fn get_info_comes_back_as_an_immediate_response() {
        let plan = passkey_plan(vec![0x04]);
        let bytes = plan
            .immediate_response
            .expect("getInfo needs no user choice");
        assert_eq!(bytes.first(), Some(&0x00), "CTAP2_OK");
    }

    #[test]
    #[serial]
    fn a_create_asks_the_user() {
        let path = with_unlocked_vault("plan_create");
        let plan = passkey_plan(request(0x01, &create_value()));
        assert!(plan.immediate_response.is_none(), "a create asks");
        assert!(plan.is_create);
        assert_eq!(plan.rp_id, "example.com");
        assert_eq!(plan.accounts, vec!["user@example.com".to_string()]);
        cleanup(&path);
    }

    #[test]
    #[serial]
    fn locked_vault_is_an_immediate_denied_response() {
        let _ = lock_vault();
        let plan = passkey_plan(request(0x01, &create_value()));
        assert_eq!(
            plan.immediate_response,
            Some(vec![0x27]),
            "OPERATION_DENIED, no dialog"
        );
    }

    #[test]
    #[serial]
    fn perform_stores_an_approved_credential() {
        let path = with_unlocked_vault("perform");
        let resp = passkey_perform(request(0x01, &create_value()), 0);
        assert_eq!(resp.first(), Some(&0x00), "CTAP2_OK");
        cleanup(&path);
    }

    #[test]
    fn denied_is_operation_denied() {
        assert_eq!(passkey_denied(), vec![0x27]);
    }
}
