//! One-time golden-vault fixture generator for the backward-compatibility
//! harness (`tests/vault_backward_compat.rs`).
//!
//! Fixtures are committed binary `.gabbro` files, sealed by the code that ships
//! each format VERSION, and then frozen forever. They are NOT regenerated on each
//! test run — that is the whole point (a round-trip can't catch a brick).
//!
//! Files are named by the compiled-in `VERSION`, so the SAME generator produces
//! the v7 pair on `master` and the v6 pair when compiled in a worktree checked out
//! at the tag that shipped VERSION 6 (`v0.1.0-alpha.4`). See
//! `tests/fixtures/FIXTURES.md` for the full recipe, including the transient
//! Argon2id-default lowering that keeps the committed fixtures cheap to open.
//!
//! Seal-time values come from the shared `fixture_spec.rs`, the same file the
//! harness asserts against, so they cannot drift.

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

    // ── Passphrase-only ──────────────────────────────────────────────────────
    let pp_path = dir.join(format!("v{v}_passphrase.gabbro"));
    save_vault(&canary_body(), FIXTURE_PASSPHRASE, &pp_path).expect("seal passphrase fixture");
    println!("wrote {}", pp_path.display());

    // ── Multi-key (passphrase + YK1 + YK2) ───────────────────────────────────
    // init_vault_with_keys seals an EMPTY body, so we then open with YK1 to get
    // the cached vault_key_master and re-seal with the canary added — exactly the
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
    reseal_vault_body(&body, &master, &mk_path).expect("re-seal multi-key fixture with canary");
    // Verify the canary actually serialises into the body we just sealed.
    let _ = serialize_vault_body(&body).expect("serialize canary body");
    println!("wrote {}", mk_path.display());
}
