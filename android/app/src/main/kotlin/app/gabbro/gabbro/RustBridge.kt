package app.gabbro.gabbro

/**
 * The autofill and passkey services run outside Flutter, so they cannot use
 * the generated Dart bridge. These JNI calls hit the same .so Flutter loads,
 * so the Rust VAULT_SESSION is shared. Implementations:
 * rust/src/api/autofill_bridge.rs and passkey_bridge.rs.
 */
object RustBridge {

    init {
        System.loadLibrary("rust_lib_gabbro")
    }

    /** Thread-safe: takes the session mutex only for the check. */
    external fun isVaultUnlocked(): Boolean

    /** `[{"id","username","url"}]`; "[]" when locked or no Login entries. */
    external fun listLoginSummaries(): String

    /** `{"id","username","password"}`; "{}" when locked, unknown, or not a Login. */
    external fun getEntry(id: String): String

    // The passkey calls return the success JSON or {"error": "..."}; check
    // "error" first. A locked vault reports an error containing "locked".

    /** Exact rp match, allow-list honoured. `{"matches":[{"entryId","rpId","userName","userDisplayName","credentialIdB64"}]}` */
    external fun passkeysForRequest(requestJson: String): String

    /**
     * Returns the W3C RegistrationResponseJSON. clientDataJsonB64 is null
     * when a privileged browser attaches its own clientDataJSON.
     */
    external fun registerPasskey(requestJson: String, clientDataJsonB64: String?): String

    /**
     * Returns the W3C AuthenticationResponseJSON. Exactly one of
     * clientDataJsonB64 (hashed here) or clientDataHashB64 (privileged caller
     * pre-hashed); the other null.
     */
    external fun signPasskeyAssertion(
        entryId: String,
        clientDataJsonB64: String?,
        clientDataHashB64: String?,
    ): String
}