package app.gabbro.gabbro

import android.content.Context
import android.util.Base64
import java.security.MessageDigest

/**
 * Per-vault SharedPreferences bookkeeping for biometric enrolment: the
 * encrypted-passphrase ciphertext + iv + the owning vault path, namespaced by a hash
 * of the vault path so each vault has its own slot.
 *
 * Deliberately free of any AndroidKeyStore calls so the per-vault storage contract is
 * unit-testable under Robolectric. The KeyStore key lifecycle (generate/delete/cipher)
 * lives in [BiometricHelper]; this object only names the alias and holds the prefs.
 */
object BiometricStore {

    private const val PREFS_FILE = "gabbro_biometric"

    /** Stable per-vault suffix: hex SHA-256 of the vault path. */
    fun suffix(vaultPath: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(vaultPath.toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }

    /** AndroidKeyStore alias for this vault's biometric key. */
    fun keyAlias(vaultPath: String): String = "gabbro_biometric_key_${suffix(vaultPath)}"

    /** True iff a complete enrolment (ciphertext + iv + matching path) exists for [vaultPath]. */
    fun has(context: Context, vaultPath: String): Boolean {
        val s = suffix(vaultPath)
        val p = prefs(context)
        return p.contains(ctKey(s)) &&
            p.contains(ivKey(s)) &&
            p.getString(pathKey(s), null) == vaultPath
    }

    /** The stored (ciphertext, iv) for [vaultPath], or null if not fully enrolled. */
    fun read(context: Context, vaultPath: String): Pair<ByteArray, ByteArray>? {
        val s = suffix(vaultPath)
        val p = prefs(context)
        val ct = p.getString(ctKey(s), null) ?: return null
        val iv = p.getString(ivKey(s), null) ?: return null
        if (p.getString(pathKey(s), null) != vaultPath) return null
        return Base64.decode(ct, Base64.NO_WRAP) to Base64.decode(iv, Base64.NO_WRAP)
    }

    fun store(context: Context, vaultPath: String, ciphertext: ByteArray, iv: ByteArray) {
        val s = suffix(vaultPath)
        prefs(context).edit()
            .putString(ctKey(s), Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            .putString(ivKey(s), Base64.encodeToString(iv, Base64.NO_WRAP))
            .putString(pathKey(s), vaultPath)
            .apply()
    }

    /** Drop this vault's enrolment slot, leaving every other vault's slot untouched. */
    fun forget(context: Context, vaultPath: String) {
        val s = suffix(vaultPath)
        prefs(context).edit()
            .remove(ctKey(s))
            .remove(ivKey(s))
            .remove(pathKey(s))
            .apply()
    }

    private fun ctKey(s: String) = "ct_$s"
    private fun ivKey(s: String) = "iv_$s"
    private fun pathKey(s: String) = "path_$s"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
}
