//! WebAuthn authenticator crypto for the passkey provider (ADR-009).
//!
//! Platform-independent core shared by the Android Credential Manager provider
//! and the Linux virtual FIDO2 authenticator: ES256 key generation, COSE_Key
//! encoding, authenticatorData assembly, and assertion signing. The private key
//! never leaves this module except as vault-entry bytes; relying parties only
//! ever receive the public key and signatures.

use p256::ecdsa::signature::Signer;
use p256::ecdsa::{Signature, SigningKey};
use rand::rngs::OsRng;
use rand::RngCore;
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

#[derive(Debug, thiserror::Error)]
pub enum WebAuthnError {
    /// The stored private key bytes do not form a valid P-256 scalar.
    #[error("invalid passkey private key")]
    InvalidPrivateKey,
}

/// A freshly generated ES256 credential key pair, vault-entry-ready.
#[derive(Zeroize, ZeroizeOnDrop)]
pub struct Es256KeyPair {
    /// P-256 private scalar, 32 bytes.
    pub private_key: Vec<u8>,
    /// WebAuthn COSE_Key (EC2/ES256/P-256), the pinned 77-byte CBOR layout.
    pub public_key_cose: Vec<u8>,
}

/// Generate an ES256 (P-256) key pair for a new passkey.
pub fn generate_es256() -> Es256KeyPair {
    let mut bytes = Zeroizing::new([0u8; 32]);
    let sk = loop {
        OsRng.fill_bytes(bytes.as_mut());
        // Rejects 0 and values >= the group order; retry odds ~2^-128.
        if let Ok(sk) = SigningKey::from_slice(bytes.as_ref()) {
            break sk;
        }
    };
    let point = sk.verifying_key().to_sec1_point(false);
    let x = point.x().expect("an uncompressed SEC1 point carries x");
    let y = point.y().expect("an uncompressed SEC1 point carries y");
    // CBOR map(5): {1: 2 (kty EC2), 3: -7 (ES256), -1: 1 (P-256), -2: x, -3: y}.
    let mut cose = Vec::with_capacity(77);
    cose.extend_from_slice(&[0xa5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01]);
    cose.push(0x21);
    cose.extend_from_slice(&[0x58, 0x20]);
    cose.extend_from_slice(x);
    cose.push(0x22);
    cose.extend_from_slice(&[0x58, 0x20]);
    cose.extend_from_slice(y);
    Es256KeyPair {
        private_key: bytes.to_vec(),
        public_key_cose: cose,
    }
}

/// authenticatorData for an assertion: rpIdHash(32) || flags(1) || counter(4).
///
/// Flags UP|UV|BE|BS (0x1d): presence and verification are satisfied by the
/// vault unlock + per-operation consent, and a vault passkey is by definition
/// synced (backup eligible and backed up). Counter stays 0 — the sanctioned
/// constant for synced passkeys.
pub fn assertion_authenticator_data(rp_id: &str) -> Vec<u8> {
    let mut ad = Vec::with_capacity(37);
    ad.extend_from_slice(&Sha256::digest(rp_id.as_bytes()));
    ad.push(0x1d);
    ad.extend_from_slice(&0u32.to_be_bytes());
    ad
}

/// authenticatorData for a registration: the assertion layout plus the AT flag
/// and attested credential data (zero AAGUID, credential id, COSE key).
pub fn registration_authenticator_data(
    rp_id: &str,
    credential_id: &[u8],
    public_key_cose: &[u8],
) -> Vec<u8> {
    let mut ad = Vec::with_capacity(37 + 16 + 2 + credential_id.len() + public_key_cose.len());
    ad.extend_from_slice(&Sha256::digest(rp_id.as_bytes()));
    // UP|UV|AT|BE|BS: assertion flags plus "attested credential data included".
    ad.push(0x5d);
    ad.extend_from_slice(&0u32.to_be_bytes());
    ad.extend_from_slice(&[0u8; 16]); // zero AAGUID: "none" attestation
    ad.extend_from_slice(&(credential_id.len() as u16).to_be_bytes());
    ad.extend_from_slice(credential_id);
    ad.extend_from_slice(public_key_cose);
    ad
}

/// The WebAuthn attestation object: canonical CBOR
/// `{"fmt": "none", "attStmt": {}, "authData": <bytes>}`.
pub fn attestation_object(auth_data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(auth_data.len() + 32);
    out.push(0xa3); // map(3)
    out.extend_from_slice(&[0x63, b'f', b'm', b't']); // text(3) "fmt"
    out.extend_from_slice(&[0x64, b'n', b'o', b'n', b'e']); // text(4) "none"
    out.extend_from_slice(&[0x67, b'a', b't', b't', b'S', b't', b'm', b't']); // text(7)
    out.push(0xa0); // empty map
    out.extend_from_slice(&[0x68, b'a', b'u', b't', b'h', b'D', b'a', b't', b'a']); // text(8)
                                                                                    // byte string, length in the shortest CBOR form that covers real sizes
    match auth_data.len() {
        n if n < 24 => out.push(0x40 + n as u8),
        n if n < 256 => {
            out.push(0x58);
            out.push(n as u8);
        }
        n => {
            out.push(0x59);
            out.extend_from_slice(&(n as u16).to_be_bytes());
        }
    }
    out.extend_from_slice(auth_data);
    out
}

/// Sign `authenticatorData || clientDataHash` with the entry's private key.
/// Returns the DER-encoded ECDSA signature WebAuthn expects for ES256.
pub fn sign_assertion(
    private_key: &[u8],
    authenticator_data: &[u8],
    client_data_hash: &[u8],
) -> Result<Vec<u8>, WebAuthnError> {
    let sk = SigningKey::from_slice(private_key).map_err(|_| WebAuthnError::InvalidPrivateKey)?;
    let mut message = Vec::with_capacity(authenticator_data.len() + client_data_hash.len());
    message.extend_from_slice(authenticator_data);
    message.extend_from_slice(client_data_hash);
    let sig: Signature = sk.sign(&message);
    message.zeroize();
    Ok(sig.to_der().as_bytes().to_vec())
}

/// Mint a credential id: 32 random bytes, unique per registration.
pub fn new_credential_id() -> Vec<u8> {
    let mut id = vec![0u8; 32];
    OsRng.fill_bytes(&mut id);
    id
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn es256_keygen_returns_a_32_byte_private_scalar() {
        let kp = generate_es256();
        assert_eq!(kp.private_key.len(), 32);
    }

    #[test]
    fn es256_public_key_encodes_as_a_webauthn_cose_ec2_map() {
        // Canonical CTAP2 COSE_Key for ES256/P-256, CBOR map of 5 entries:
        //   {1: 2 (kty EC2), 3: -7 (ES256), -1: 1 (P-256), -2: x, -3: y}
        // Fixed layout, 77 bytes. Offsets pinned so any encoder change that
        // would break relying parties fails here first.
        let kp = generate_es256();
        let c = &kp.public_key_cose;
        assert_eq!(c.len(), 77);
        assert_eq!(&c[..8], &[0xa5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21]);
        assert_eq!(&c[8..10], &[0x58, 0x20], "x is a 32-byte bstr");
        assert_eq!(c[42], 0x22, "label -3 (y) follows x");
        assert_eq!(&c[43..45], &[0x58, 0x20], "y is a 32-byte bstr");
    }

    #[test]
    fn keygen_is_not_deterministic() {
        let a = generate_es256();
        let b = generate_es256();
        assert_ne!(a.private_key, b.private_key);
        assert_ne!(a.public_key_cose, b.public_key_cose);
    }

    #[test]
    fn authenticator_data_pins_rp_hash_flags_and_zero_counter() {
        use sha2::{Digest, Sha256};
        let ad = assertion_authenticator_data("example.com");
        assert_eq!(ad.len(), 37, "rpIdHash(32) + flags(1) + counter(4)");
        assert_eq!(&ad[..32], Sha256::digest(b"example.com").as_slice());
        // UP (0x01) + UV (0x04) + BE (0x08) + BS (0x10) = 0x1d: user present,
        // verified by the vault unlock, and the credential is synced (backup
        // eligible + backed up) — the truthful flags for a vault passkey.
        assert_eq!(ad[32], 0x1d);
        // Constant zero counter — the WebAuthn-sanctioned value for synced
        // passkeys; relying parties must tolerate it.
        assert_eq!(&ad[33..37], &[0, 0, 0, 0]);
    }

    #[test]
    fn assertion_signature_verifies_against_the_public_key() {
        use p256::ecdsa::signature::Verifier;
        let kp = generate_es256();
        let auth_data = assertion_authenticator_data("example.com");
        let client_data_hash = [0x42u8; 32];

        let der = sign_assertion(&kp.private_key, &auth_data, &client_data_hash)
            .expect("signing with a freshly generated key must succeed");

        // Verify over exactly authenticatorData || clientDataHash — what the
        // relying party reconstructs.
        let vk = verifying_key_from_cose(&kp.public_key_cose);
        let mut message = auth_data.clone();
        message.extend_from_slice(&client_data_hash);
        let sig = p256::ecdsa::Signature::from_der(&der).expect("DER signature");
        assert!(vk.verify(&message, &sig).is_ok());
    }

    #[test]
    fn sign_assertion_refuses_a_malformed_private_key() {
        let auth_data = assertion_authenticator_data("example.com");
        assert!(sign_assertion(&[0u8; 31], &auth_data, &[0u8; 32]).is_err());
        assert!(sign_assertion(&[0u8; 32], &auth_data, &[0u8; 32]).is_err());
    }

    #[test]
    fn signing_is_deterministic_so_repeat_requests_emit_identical_bytes() {
        // RFC 6979 nonces: the same key + message must always produce the same
        // DER signature. Pins the Android-visible bytes against a silent switch
        // to randomised ECDSA while the core is reworked for the Linux daemon.
        let kp = generate_es256();
        let ad = assertion_authenticator_data("example.com");
        let a = sign_assertion(&kp.private_key, &ad, &[0x42u8; 32]).unwrap();
        let b = sign_assertion(&kp.private_key, &ad, &[0x42u8; 32]).unwrap();
        assert_eq!(a, b);
    }

    // Hand-derived from RFC 8949: map(3), text keys "fmt"/"attStmt"/"authData",
    // "none", empty map. Independent of the encoder under test.
    const ATT_OBJ_PREFIX: &[u8] = b"\xa3\x63fmt\x64none\x67attStmt\xa0\x68authData";

    #[test]
    fn attestation_object_golden_pins_all_three_cbor_length_encodings() {
        // < 24 bytes: length lives in the initial byte (0x40 + n).
        let small = attestation_object(&[1, 2, 3]);
        assert_eq!(small, [ATT_OBJ_PREFIX, &[0x43, 1, 2, 3]].concat());

        // 24..=255 bytes: 0x58 + one length byte (the real ~164-byte case).
        let mid_payload = [0xAB; 100];
        let mid = attestation_object(&mid_payload);
        assert_eq!(
            mid,
            [ATT_OBJ_PREFIX, &[0x58, 100], mid_payload.as_slice()].concat()
        );

        // >= 256 bytes: 0x59 + two length bytes, big-endian.
        let large_payload = [0xCD; 300];
        let large = attestation_object(&large_payload);
        assert_eq!(
            large,
            [
                ATT_OBJ_PREFIX,
                &[0x59, 0x01, 0x2C],
                large_payload.as_slice()
            ]
            .concat()
        );
    }

    #[test]
    fn credential_ids_are_32_random_bytes_and_unique() {
        let a = new_credential_id();
        let b = new_credential_id();
        assert_eq!(a.len(), 32);
        assert_eq!(b.len(), 32);
        assert_ne!(a, b);
    }

    /// Test-only COSE decoder: extracts x||y from the pinned 77-byte layout the
    /// encoder test above locks down.
    fn verifying_key_from_cose(cose: &[u8]) -> p256::ecdsa::VerifyingKey {
        let mut sec1 = vec![0x04u8];
        sec1.extend_from_slice(&cose[10..42]);
        sec1.extend_from_slice(&cose[45..77]);
        p256::ecdsa::VerifyingKey::from_sec1_bytes(&sec1).expect("COSE carries a valid point")
    }
}
