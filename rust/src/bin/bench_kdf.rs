//! Argon2id parameter benchmark.
//!
//! Run with: cargo run --bin bench_kdf --release
//!
//! Used to validate that the KDF parameters in ADR-006 produce an
//! acceptable derivation time on the target hardware. Re-run this
//! when changing m_cost, t_cost, or p_cost, or when targeting a
//! new minimum device. Target range: 0.5s – 1.0s on the development
//! machine; expect 1.5–2.5s on a mid-range Android phone.
//!
//! One-shot Argon2id benchmark — run with:
//! cargo run --bin bench_kdf --release

use argon2::{Argon2, Params, Version, Algorithm};
use std::time::Instant;

fn main() {
    let password = b"correct horse battery staple";
    let salt = b"gabbro__salt____"; // 16 bytes exactly

    let params = Params::new(
        65536, // m_cost: 64 MiB in KiB
        25,     // t_cost: iterations
        4,     // p_cost: parallelism
        Some(96), // output length: 96 bytes
    ).expect("valid params");

    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut output = vec![0u8; 96];

    println!("Running Argon2id (m=64MiB, t=25, p=4) ...");
    let start = Instant::now();
    argon2.hash_password_into(password, salt, &mut output)
        .expect("hash failed");
    let elapsed = start.elapsed();

    println!("Done in {:.3}s", elapsed.as_secs_f64());
    println!("First 8 bytes of output: {:?}", &output[..8]);
}