package app.gabbro.gabbro

/**
 * RustBridge — thin Kotlin wrapper around the native Rust functions needed
 * by GabbroAutofillService.
 *
 * The autofill service runs in Gabbro's process but outside Flutter, so it
 * cannot use the generated Dart bridge. These JNI declarations call the same
 * compiled Rust .so that Flutter uses — the VAULT_SESSION global is shared.
 *
 * The native library is loaded by the Flutter engine on first launch.
 * The autofill service only runs while Gabbro's process is alive, so the
 * library will always be loaded before any service callback fires.
 *
 * Native functions are implemented in rust/src/api/autofill_bridge.rs
 * (added in the same session as this file).
 */
object RustBridge {

    init {
        System.loadLibrary("rust_lib_gabbro")
    }

    /**
     * Returns true if the Rust vault session is currently unlocked
     * (i.e. VAULT_SESSION holds a live VaultSession).
     *
     * Safe to call from any thread — the Rust implementation acquires
     * the session mutex, checks Option::is_some(), and releases immediately.
     */
    external fun isVaultUnlocked(): Boolean

    /**
     * Returns a JSON string encoding all Login entry summaries in the session.
     * Shape: `[{"id":"...","username":"...","url":"..."}]`
     * Returns "[]" if the vault is locked or contains no Login entries.
     * Parse with org.json.JSONArray — no new dependency needed.
     */
    external fun listLoginSummaries(): String

    /**
     * Returns a JSON string encoding id, username, and password for a single
     * Login entry looked up by UUID.
     * Shape: `{"id":"...","username":"...","password":"..."}`
     * Returns "{}" if the vault is locked, the id is not found, or the entry
     * is not a Login entry.
     */
    external fun getEntry(id: String): String
}