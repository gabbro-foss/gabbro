package app.gabbro.gabbro

import android.content.Context
import android.util.Base64
import java.security.MessageDigest

/**
 * Free of AndroidKeyStore calls so the per-vault storage contract is testable
 * under Robolectric; the key lifecycle lives in [BiometricHelper].
 */
object BiometricStore {

    private const val PREFS_FILE = "gabbro_biometric"

    fun suffix(vaultPath: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(vaultPath.toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }

    fun keyAlias(vaultPath: String): String = "gabbro_biometric_key_${suffix(vaultPath)}"

    fun has(context: Context, vaultPath: String): Boolean {
        val s = suffix(vaultPath)
        val p = prefs(context)
        return p.contains(ctKey(s)) &&
            p.contains(ivKey(s)) &&
            p.getString(pathKey(s), null) == vaultPath
    }

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
