//! Vault state-machine fuzzer — the exploratory layer above the deterministic
//! `vault_backward_compat` gate.
//!
//! # What this does
//!
//! The gate proves two *hand-picked* journeys (vault A passphrase change, vault B
//! interleaved change + rotation). This fuzzer instead applies a *random* order of
//! `{change_passphrase, add_key, remove_key}` to a frozen golden v11 vault and, after
//! every single step, asserts the brick-prevention invariants hold. It is the
//! Hypothesis-style "find the interleaving I didn't think of" net for the multi-key
//! state machine.
//!
//! # Why it is `#[ignore]`'d
//!
//! Every `change_passphrase` re-seals with production-strength Argon2id (the public
//! seal API hard-codes `Argon2idParams::default()`), which is ~18 s/op in a *debug*
//! `cargo test` build and ~sub-second in `--release`. So it must NOT run in the
//! routine debug `cargo test -q`. Run it explicitly, in release:
//!
//! ```text
//! cargo test --release --test vault_state_machine_fuzz -- --ignored
//! ```
//!
//! Widen the search with `GABBRO_FUZZ_CASES=64 cargo test --release \
//!   --test vault_state_machine_fuzz -- --ignored`.
//!
//! # Determinism
//!
//! The RNG is seeded from a fixed constant, so a given `(seed, cases)` always walks
//! the same sequences — a gate must never flake. When a run fails it prints the
//! exact case index + operation log; reproduce it, minimise by hand, and promote it
//! into `vault_backward_compat.rs` as a fixed regression test. No `proptest`
//! dependency: `rand` (already a direct dependency) gives us `SliceRandom::choose`
//! (the `np.random.choice` analogue) and a seedable `StdRng`.

use rand::rngs::StdRng;
use rand::seq::SliceRandom;
use rand::{Rng, SeedableRng};

use rust_lib_gabbro::api::vault::{
    add_yubikey_to_vault, change_passphrase_with_keys, load_vault_with_key_record,
    remove_yubikey_from_vault,
};
use rust_lib_gabbro::vault::entry::VaultEntry;
use rust_lib_gabbro::vault::file_format::VERSION;
use rust_lib_gabbro::vault::io::read_vault;
use rust_lib_gabbro::vault::serialization::{serialize_vault_body, VaultBody};
use std::path::{Path, PathBuf};

// Shared fixture spec (passphrase, canary, YubiKey material). Same include the gate
// and the generator use, so seal-time and assert-time values can never drift.
include!("fixtures/fixture_spec.rs");

const FIXED_SEED: u64 = 0x6761_6262_726f_2031; // "gabbro 1"
const DEFAULT_CASES: usize = 12;
const MAX_STEPS: usize = 6;

/// One YubiKey's fixed fake material, named for readable failure logs.
struct KeyMat {
    cred: &'static [u8],
    hmac: &'static [u8; 32],
    salt: [u8; 32],
    name: &'static str,
}

/// The four keys available to the fuzzer. The fixture registers YK1+YK2; YK3/YK4
/// start unregistered. A removed key returns to the pool, so re-registration of a
/// previously-removed credential is exercised too.
fn key_pool() -> [KeyMat; 4] {
    [
        KeyMat {
            cred: YK1_CRED,
            hmac: YK1_HMAC,
            salt: YK1_SALT,
            name: "YK1",
        },
        KeyMat {
            cred: YK2_CRED,
            hmac: YK2_HMAC,
            salt: YK2_SALT,
            name: "YK2",
        },
        KeyMat {
            cred: YK3_CRED,
            hmac: YK3_HMAC,
            salt: YK3_SALT,
            name: "YK3",
        },
        KeyMat {
            cred: YK4_CRED,
            hmac: YK4_HMAC,
            salt: YK4_SALT,
            name: "YK4",
        },
    ]
}

struct TempVault {
    path: PathBuf,
}
impl Drop for TempVault {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
        let _ = std::fs::remove_file(format!("{}.bak", self.path.display()));
    }
}

/// Fresh temp copy of a committed fixture so the golden file is never mutated.
fn temp_copy(fixture_name: &str, tag: usize) -> TempVault {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let src = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/vaults")
        .join(fixture_name);
    let path = std::env::temp_dir().join(format!(
        "gabbro-fuzz-{}-{}-{}",
        std::process::id(),
        tag,
        nanos
    ));
    std::fs::copy(src, &path).expect("copy fixture to temp");
    TempVault { path }
}

fn has_canary(body: &VaultBody) -> bool {
    body.entries.iter().any(|e| {
        matches!(e, VaultEntry::Login(le)
            if le.title == CANARY_TITLE && le.password == CANARY_PASSWORD)
    })
}

/// In-memory model of the vault's authorisation state, mirrored against disk.
struct Model {
    registered: Vec<usize>, // indices into key_pool()
    passphrase: Vec<u8>,
}

impl Model {
    fn fresh() -> Self {
        Model {
            registered: vec![0, 1], // YK1 + YK2, as the fixture was sealed
            passphrase: FIXTURE_PASSPHRASE.to_vec(),
        }
    }

    fn unregistered(&self) -> Vec<usize> {
        (0..4).filter(|i| !self.registered.contains(i)).collect()
    }
}

/// Every registered key opens the vault under the current passphrase with the
/// canary intact (the core brick-prevention property), regardless of on-disk
/// VERSION. `log` is the running operation history, printed verbatim if any
/// assertion blows so the failure is reproducible. Used at baseline, where a
/// pre-current fixture is not yet migrated.
fn assert_unlockable(path: &Path, model: &Model, pool: &[KeyMat; 4], log: &[String]) {
    for &r in &model.registered {
        let k = &pool[r];
        let (body, _m, _w) = load_vault_with_key_record(&model.passphrase, k.hmac, k.cred, path)
            .unwrap_or_else(|e| {
                panic!(
                    "{} must still open the vault; history: [{}]: {e}",
                    k.name,
                    log.join(" -> ")
                )
            });
        assert!(
            has_canary(&body),
            "canary must survive; opened with {}; history: [{}]",
            k.name,
            log.join(" -> ")
        );
    }
}

/// After every mutation: the vault is never bricked (opens with every registered
/// key, canary intact) and stays at the current VERSION. Every openable vault is
/// v11+, a single key-derivation era, so every re-seal — with or without a
/// passphrase rebuild — tags the current VERSION.
fn assert_invariants(path: &Path, model: &Model, pool: &[KeyMat; 4], log: &[String]) {
    let on_disk = read_vault(path)
        .unwrap_or_else(|e| panic!("read_vault failed after [{}]: {e}", log.join(" -> ")));
    assert_eq!(
        on_disk.version,
        VERSION,
        "every mutation must re-seal at the current VERSION; history: [{}]",
        log.join(" -> ")
    );
    assert_unlockable(path, model, pool, log);
}

/// End-of-sequence negative checks: nothing that should be locked out can open it.
fn assert_lockout(path: &Path, model: &Model, pool: &[KeyMat; 4], log: &[String]) {
    // Every UNregistered key must be refused under the current passphrase.
    for u in model.unregistered() {
        let k = &pool[u];
        assert!(
            load_vault_with_key_record(&model.passphrase, k.hmac, k.cred, path).is_err(),
            "unregistered {} must not open the vault; history: [{}]",
            k.name,
            log.join(" -> ")
        );
    }
    // If the passphrase was ever changed, the original must no longer open it with
    // any still-registered key.
    if model.passphrase != FIXTURE_PASSPHRASE {
        for &r in &model.registered {
            let k = &pool[r];
            assert!(
                load_vault_with_key_record(FIXTURE_PASSPHRASE, k.hmac, k.cred, path).is_err(),
                "the original passphrase must be rejected after a change (key {}); history: [{}]",
                k.name,
                log.join(" -> ")
            );
        }
    }
}

#[test]
#[ignore = "production Argon2id per passphrase change; run explicitly in --release"]
fn random_op_sequences_preserve_unlockability() {
    let cases: usize = std::env::var("GABBRO_FUZZ_CASES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(DEFAULT_CASES);
    let pool = key_pool();
    let mut rng = StdRng::seed_from_u64(FIXED_SEED);

    // v11 is the oldest openable format, so it is the only fixture the fuzzer can
    // start from. Append the older format here if a future VERSION changes key
    // derivation and re-introduces a migration path worth fuzzing.
    const FIXTURES: [&str; 1] = ["v11_multikey_2keys.gabbro"];

    for case in 0..cases {
        let fixture_name = FIXTURES[case % FIXTURES.len()];
        let tv = temp_copy(fixture_name, case);
        let path = tv.path.as_path();
        let mut model = Model::fresh();
        let mut log: Vec<String> = vec![format!("case#{case} start({fixture_name}: YK1,YK2)")];

        // Baseline: the freshly-copied fixture opens with every key, at the current
        // VERSION (it is the current format, not an older one being migrated).
        assert_unlockable(path, &model, &pool, &log);
        let start_version = read_vault(path)
            .unwrap_or_else(|e| panic!("baseline read_vault failed ({fixture_name}): {e}"))
            .version;
        assert_eq!(
            start_version, VERSION,
            "fixture {fixture_name} must be at the current VERSION"
        );

        let steps = rng.gen_range(1..=MAX_STEPS);
        for _ in 0..steps {
            // Which operations are legal in the current state?
            let mut choices: Vec<&str> = vec!["change_passphrase"];
            if model.registered.len() < 4 {
                choices.push("add_key");
            }
            if model.registered.len() > 1 {
                choices.push("remove_key");
            }
            let op = *choices.choose(&mut rng).unwrap();

            // Authorise the mutation with a random currently-registered key under the
            // current passphrase — the same one-tap authorisation the app performs.
            let auth = *model.registered.choose(&mut rng).unwrap();
            let ak = &pool[auth];
            let (body, master, wrapping) =
                load_vault_with_key_record(&model.passphrase, ak.hmac, ak.cred, path)
                    .unwrap_or_else(|e| {
                        panic!(
                            "authorise with {} failed; history: [{}]: {e}",
                            ak.name,
                            log.join(" -> ")
                        )
                    });
            let pt = serialize_vault_body(&body).expect("serialize vault body");

            match op {
                "change_passphrase" => {
                    let new_pass = format!("fuzz-pp-{case}-{}", log.len()).into_bytes();
                    change_passphrase_with_keys(&model.passphrase, &new_pass, &master, &pt, path)
                        .unwrap_or_else(|e| {
                            panic!(
                                "change_passphrase failed; history: [{}]: {e}",
                                log.join(" -> ")
                            )
                        });
                    model.passphrase = new_pass;
                    log.push(format!("change_passphrase(auth={})", ak.name));
                }
                "add_key" => {
                    let cand = model.unregistered();
                    let idx = *cand.choose(&mut rng).unwrap();
                    let nk = &pool[idx];
                    let wrapping = wrapping.expect("multi-key vault must expose a wrapping_key");
                    add_yubikey_to_vault(
                        &pt,
                        &wrapping,
                        &master,
                        nk.cred.to_vec(),
                        nk.hmac,
                        nk.salt,
                        path,
                    )
                    .unwrap_or_else(|e| {
                        panic!(
                            "add {} failed; history: [{}]: {e}",
                            nk.name,
                            log.join(" -> ")
                        )
                    });
                    model.registered.push(idx);
                    log.push(format!("add({}, auth={})", nk.name, ak.name));
                }
                "remove_key" => {
                    // Remove any registered key (possibly the one we authorised with —
                    // master is already in hand), keeping the floor of one.
                    let victim = *model.registered.choose(&mut rng).unwrap();
                    let vk = &pool[victim];
                    remove_yubikey_from_vault(&pt, &master, vk.cred, path).unwrap_or_else(|e| {
                        panic!(
                            "remove {} failed; history: [{}]: {e}",
                            vk.name,
                            log.join(" -> ")
                        )
                    });
                    model.registered.retain(|&i| i != victim);
                    log.push(format!("remove({}, auth={})", vk.name, ak.name));
                }
                _ => unreachable!(),
            }

            assert_invariants(path, &model, &pool, &log);
        }

        // Final lock-out checks once the sequence is complete.
        assert_lockout(path, &model, &pool, &log);
    }
}
