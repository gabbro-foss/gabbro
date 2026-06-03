package app.gabbro.gabbro

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object BiometricHelper {

    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "gabbro_biometric_key"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val PREFS_FILE = "gabbro_biometric"
    private const val KEY_CIPHERTEXT = "ct"
    private const val KEY_IV = "iv"
    private const val KEY_VAULT_PATH = "vault_path"

    // ── Public API ────────────────────────────────────────────────────────────

    fun isAvailable(context: Context): Boolean =
        BiometricManager.from(context)
            .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
                BiometricManager.BIOMETRIC_SUCCESS

    fun isEnrolled(context: Context, vaultPath: String): Boolean {
        val p = prefs(context)
        return p.contains(KEY_CIPHERTEXT) &&
               p.contains(KEY_IV) &&
               p.getString(KEY_VAULT_PATH, null) == vaultPath
    }

    fun enroll(
        activity: FragmentActivity,
        vaultPath: String,
        passphrase: ByteArray,
        promptTitle: String,
        promptSubtitle: String,
        onSuccess: () -> Unit,
        onError: (String) -> Unit,
    ) {
        try {
            deleteKey()
            generateKey()
            val cipher = encryptCipher()
            val executor = ContextCompat.getMainExecutor(activity)
            BiometricPrompt(activity, executor, object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    try {
                        val c = result.cryptoObject?.cipher
                            ?: return onError("No cipher in result")
                        val iv = c.iv
                        val ciphertext = c.doFinal(passphrase)
                        passphrase.fill(0)
                        storeEncrypted(activity, vaultPath, ciphertext, iv)
                        onSuccess()
                    } catch (e: Exception) {
                        passphrase.fill(0)
                        onError(e.message ?: "Encryption failed")
                    }
                }

                override fun onAuthenticationError(code: Int, msg: CharSequence) {
                    passphrase.fill(0)
                    onError(msg.toString())
                }

                override fun onAuthenticationFailed() { /* retry handled by system */ }
            }).authenticate(buildPromptInfo(promptTitle, promptSubtitle, activity),
                BiometricPrompt.CryptoObject(cipher))
        } catch (e: Exception) {
            passphrase.fill(0)
            onError(e.message ?: "Enrollment failed")
        }
    }

    fun authenticate(
        activity: FragmentActivity,
        vaultPath: String,
        promptTitle: String,
        promptSubtitle: String,
        onSuccess: (ByteArray) -> Unit,
        onError: (String) -> Unit,
    ) {
        val prefs = prefs(activity)
        val ctB64 = prefs.getString(KEY_CIPHERTEXT, null)
        val ivB64 = prefs.getString(KEY_IV, null)
        val storedPath = prefs.getString(KEY_VAULT_PATH, null)
        if (ctB64 == null || ivB64 == null || storedPath != vaultPath) {
            onError("NOT_ENROLLED")
            return
        }
        val ciphertext = Base64.decode(ctB64, Base64.NO_WRAP)
        val iv = Base64.decode(ivB64, Base64.NO_WRAP)

        val cipher = try {
            decryptCipher(iv)
        } catch (e: KeyPermanentlyInvalidatedException) {
            unenroll(activity)
            onError("KEY_INVALIDATED")
            return
        } catch (e: Exception) {
            onError(e.message ?: "Key error")
            return
        }

        val executor = ContextCompat.getMainExecutor(activity)
        BiometricPrompt(activity, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                try {
                    val c = result.cryptoObject?.cipher
                        ?: return onError("No cipher in result")
                    onSuccess(c.doFinal(ciphertext))
                } catch (e: Exception) {
                    onError(e.message ?: "Decryption failed")
                }
            }

            override fun onAuthenticationError(code: Int, msg: CharSequence) =
                onError(msg.toString())

            override fun onAuthenticationFailed() {}
        }).authenticate(buildPromptInfo(promptTitle, promptSubtitle, activity),
            BiometricPrompt.CryptoObject(cipher))
    }

    fun unenroll(context: Context) {
        prefs(context).edit()
            .remove(KEY_CIPHERTEXT)
            .remove(KEY_IV)
            .apply()
        deleteKey()
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)

    private fun storeEncrypted(
        context: Context,
        vaultPath: String,
        ciphertext: ByteArray,
        iv: ByteArray,
    ) {
        prefs(context).edit()
            .putString(KEY_CIPHERTEXT, Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            .putString(KEY_IV, Base64.encodeToString(iv, Base64.NO_WRAP))
            .putString(KEY_VAULT_PATH, vaultPath)
            .apply()
    }

    private fun generateKey() {
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER).apply {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .setUserAuthenticationRequired(true)
                    .setInvalidatedByBiometricEnrollment(true)
                    .build()
            )
            generateKey()
        }
    }

    private fun getKey(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE_PROVIDER).also { it.load(null) }
        return ks.getKey(KEY_ALIAS, null) as SecretKey
    }

    private fun deleteKey() {
        val ks = KeyStore.getInstance(KEYSTORE_PROVIDER).also { it.load(null) }
        if (ks.containsAlias(KEY_ALIAS)) ks.deleteEntry(KEY_ALIAS)
    }

    private fun encryptCipher(): Cipher =
        Cipher.getInstance(TRANSFORMATION).also { it.init(Cipher.ENCRYPT_MODE, getKey()) }

    private fun decryptCipher(iv: ByteArray): Cipher =
        Cipher.getInstance(TRANSFORMATION).also {
            it.init(Cipher.DECRYPT_MODE, getKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        }

    private fun buildPromptInfo(
        title: String,
        subtitle: String,
        context: Context,
    ): BiometricPrompt.PromptInfo =
        BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButtonText(
                context.getString(android.R.string.cancel)
            )
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()
}
