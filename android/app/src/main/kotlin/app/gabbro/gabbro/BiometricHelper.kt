package app.gabbro.gabbro

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Biometric enrolment is per vault: each vault gets its own AndroidKeyStore key
 * (alias via [BiometricStore.keyAlias]) and its own SharedPreferences slot (via
 * [BiometricStore]). Enrolling or unenrolling one vault never touches another.
 * Biometric is also per device — the key is hardware-bound and never travels with the
 * vault file, so a vault synced across devices carries no biometric state.
 */
object BiometricHelper {

    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128

    // ── Public API ────────────────────────────────────────────────────────────

    fun isAvailable(context: Context): Boolean =
        BiometricManager.from(context)
            .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
                BiometricManager.BIOMETRIC_SUCCESS

    fun isEnrolled(context: Context, vaultPath: String): Boolean =
        BiometricStore.has(context, vaultPath)

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
            deleteKey(vaultPath)
            generateKey(vaultPath)
            val cipher = encryptCipher(vaultPath)
            val executor = ContextCompat.getMainExecutor(activity)
            BiometricPrompt(activity, executor, object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    try {
                        val c = result.cryptoObject?.cipher
                            ?: return onError("No cipher in result")
                        val iv = c.iv
                        val ciphertext = c.doFinal(passphrase)
                        passphrase.fill(0)
                        BiometricStore.store(activity, vaultPath, ciphertext, iv)
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
        val stored = BiometricStore.read(activity, vaultPath)
        if (stored == null) {
            onError("NOT_ENROLLED")
            return
        }
        val (ciphertext, iv) = stored

        val cipher = try {
            decryptCipher(vaultPath, iv)
        } catch (e: KeyPermanentlyInvalidatedException) {
            unenroll(activity, vaultPath)
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

    fun unenroll(context: Context, vaultPath: String) {
        BiometricStore.forget(context, vaultPath)
        deleteKey(vaultPath)
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun generateKey(vaultPath: String) {
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER).apply {
            init(
                KeyGenParameterSpec.Builder(
                    BiometricStore.keyAlias(vaultPath),
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

    private fun getKey(vaultPath: String): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE_PROVIDER).also { it.load(null) }
        return ks.getKey(BiometricStore.keyAlias(vaultPath), null) as SecretKey
    }

    private fun deleteKey(vaultPath: String) {
        val ks = KeyStore.getInstance(KEYSTORE_PROVIDER).also { it.load(null) }
        val alias = BiometricStore.keyAlias(vaultPath)
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)
    }

    private fun encryptCipher(vaultPath: String): Cipher =
        Cipher.getInstance(TRANSFORMATION).also { it.init(Cipher.ENCRYPT_MODE, getKey(vaultPath)) }

    private fun decryptCipher(vaultPath: String, iv: ByteArray): Cipher =
        Cipher.getInstance(TRANSFORMATION).also {
            it.init(Cipher.DECRYPT_MODE, getKey(vaultPath), GCMParameterSpec(GCM_TAG_BITS, iv))
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
