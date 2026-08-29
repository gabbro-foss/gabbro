//! `cargo run --bin bench_kdf --release`. Re-run when the ADR-006 Argon2id
//! parameters or the minimum target device change. Target: 0.5-1.0 s on the
//! dev machine, 1.5-2.5 s on a mid-range phone.

use argon2::{Algorithm, Argon2, Params, Version};
use std::time::Instant;

fn main() {
    let password = b"correct horse battery staple";
    let salt = b"gabbro__salt____"; // 16 bytes exactly

    let params = Params::new(
        65536,    // m_cost: 64 MiB in KiB
        25,       // t_cost: iterations
        4,        // p_cost: parallelism
        Some(96), // output length: 96 bytes
    )
    .expect("valid params");

    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut output = vec![0u8; 96];

    println!("Running Argon2id (m=64MiB, t=25, p=4) ...");
    let start = Instant::now();
    argon2
        .hash_password_into(password, salt, &mut output)
        .expect("hash failed");
    let elapsed = start.elapsed();

    println!("Done in {:.3}s", elapsed.as_secs_f64());
    println!("First 8 bytes of output: {:?}", &output[..8]);
}
