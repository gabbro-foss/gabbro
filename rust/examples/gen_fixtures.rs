//! Golden-vault generator for `tests/vault_backward_compat.rs`. Fixtures are
//! sealed once by the code shipping each VERSION and frozen; regenerating them
//! per run would turn the gate into a round-trip that cannot catch a brick.
//! Named by the compiled-in `VERSION`, so the same generator builds older pairs
//! from a checkout at the shipping tag. Recipe: `tests/fixtures/FIXTURES.md`.
//! Values come from the shared `fixture_spec.rs` so they cannot drift.

use rust_lib_gabbro::api::vault::{load_vault_with_key_record, reseal_vault_body, save_vault};
use rust_lib_gabbro::api::vault_bridge::init_vault_with_keys;
use rust_lib_gabbro::vault::file_format::VERSION;
use rust_lib_gabbro::vault::serialization::serialize_vault_body;
use std::path::PathBuf;

include!("../tests/fixtures/fixture_spec.rs");

fn vaults_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/vaults")
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let dir = vaults_dir();
    std::fs::create_dir_all(&dir).expect("create fixtures/vaults dir");
    let v = VERSION;

    let pp_path = dir.join(format!("v{v}_passphrase.gabbro"));
    save_vault(&canary_body(), FIXTURE_PASSPHRASE, &pp_path).expect("seal passphrase fixture");
    println!("wrote {}", pp_path.display());

    // init_vault_with_keys seals an EMPTY body, so we then open with YK1 to get
    // the cached vault_key_master and re-seal with the canary added - exactly the
    // CRUD path the app uses. reseal runs no Argon2 (cheap).
    let mk_path = dir.join(format!("v{v}_multikey_2keys.gabbro"));
    init_vault_with_keys(
        FIXTURE_PASSPHRASE.to_vec(),
        multikey_init_keys(),
        mk_path.to_string_lossy().into_owned(),
        Some(FIXTURE_ALIAS.to_string()),
    )
    .await
    .expect("create multi-key fixture vault");

    let (mut body, master, _wrapping) =
        load_vault_with_key_record(FIXTURE_PASSPHRASE, YK1_HMAC, YK1_CRED, &mk_path)
            .expect("open multi-key fixture with YK1");
    body.entries.push(canary_entry());
    body.entries.push(canary_passkey_entry());
    reseal_vault_body(&body, &master, &mk_path).expect("re-seal multi-key fixture with canary");
    // Verify the canary actually serialises into the body we just sealed.
    let _ = serialize_vault_body(&body).expect("serialize canary body");
    println!("wrote {}", mk_path.display());
}
