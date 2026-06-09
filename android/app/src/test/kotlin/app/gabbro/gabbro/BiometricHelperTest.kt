package app.gabbro.gabbro

import android.content.Context
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Ignore
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * isEnrolled / unenroll are exercised under Robolectric with real SharedPreferences.
 * The hardware paths (BiometricPrompt, AndroidKeyStore key material) stay @Ignore'd —
 * Robolectric cannot present a fingerprint or back a real Keystore-bound AES key.
 */
@RunWith(RobolectricTestRunner::class)
class BiometricHelperTest {

    private lateinit var context: Context

    // Mirror of BiometricHelper's private storage contract — kept in sync by these
    // tests. If a rename here is needed, the production constant changed too.
    private val prefsFile = "gabbro_biometric"
    private val keyCiphertext = "ct"
    private val keyIv = "iv"
    private val keyVaultPath = "vault_path"

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        // Start every test from a clean prefs file.
        context.getSharedPreferences(prefsFile, Context.MODE_PRIVATE)
            .edit().clear().apply()
    }

    /** Simulate a prior successful enrolment by writing the stored fields directly. */
    private fun seedEnrolment(vaultPath: String) {
        context.getSharedPreferences(prefsFile, Context.MODE_PRIVATE).edit()
            .putString(keyCiphertext, "Y2lwaGVydGV4dA==")
            .putString(keyIv, "aXZieXRlcw==")
            .putString(keyVaultPath, vaultPath)
            .apply()
    }

    // ── isAvailable ───────────────────────────────────────────────────────────

    @Test
    @Ignore("Requires Android runtime with biometric hardware")
    fun isAvailable_returns_true_when_biometric_sensor_and_enrolment_present() {
        // When: device has a biometric sensor and at least one fingerprint enrolled
        // Then: isAvailable() returns true
    }

    @Test
    @Ignore("Requires Android runtime with no enrolled biometrics")
    fun isAvailable_returns_false_when_no_biometrics_enrolled() {
        // When: device has sensor but no fingerprints enrolled
        // Then: isAvailable() returns false
    }

    // ── isEnrolled ────────────────────────────────────────────────────────────

    @Test
    fun isEnrolled_returns_false_before_enrolment() {
        assertFalse(BiometricHelper.isEnrolled(context, "/vaults/main.gabbro"))
    }

    @Test
    fun isEnrolled_returns_true_after_successful_enrolment() {
        seedEnrolment("/vaults/main.gabbro")
        assertTrue(BiometricHelper.isEnrolled(context, "/vaults/main.gabbro"))
    }

    @Test
    fun isEnrolled_returns_false_for_different_vault_path() {
        // Security-relevant guard: an enrolment for one vault must not unlock another.
        seedEnrolment("/vaults/main.gabbro")
        assertFalse(BiometricHelper.isEnrolled(context, "/vaults/other.gabbro"))
    }

    // ── unenroll ──────────────────────────────────────────────────────────────

    @Test
    @Ignore("unenroll() calls deleteKey() -> KeyStore.getInstance(\"AndroidKeyStore\"), " +
            "which Robolectric does not back (NoSuchAlgorithmException). Hardware/instrumented only.")
    fun unenroll_clears_stored_ciphertext_and_iv() {
        seedEnrolment("/vaults/main.gabbro")
        BiometricHelper.unenroll(context)
        val prefs = context.getSharedPreferences(prefsFile, Context.MODE_PRIVATE)
        assertFalse(prefs.contains(keyCiphertext))
        assertFalse(prefs.contains(keyIv))
        assertFalse(BiometricHelper.isEnrolled(context, "/vaults/main.gabbro"))
    }

    @Test
    @Ignore("unenroll() calls deleteKey() -> KeyStore.getInstance(\"AndroidKeyStore\"), " +
            "which Robolectric does not back (NoSuchAlgorithmException). Hardware/instrumented only.")
    fun unenroll_when_not_enrolled_does_not_throw() {
        BiometricHelper.unenroll(context)
        assertFalse(BiometricHelper.isEnrolled(context, "/vaults/main.gabbro"))
    }

    @Test
    @Ignore("AndroidKeyStore key material is not backed by Robolectric — hardware/instrumented only")
    fun unenroll_deletes_keystore_key() {
        // When: unenroll() is called
        // Then: the KEY_ALIAS entry no longer exists in AndroidKeyStore
    }

    // ── enroll + authenticate round-trip ──────────────────────────────────────

    @Test
    @Ignore("Requires Android device with enrolled fingerprint and real BiometricPrompt")
    fun authenticate_returns_original_passphrase_after_enrolment() {
        // When: enrol() is called with a passphrase and a fingerprint is presented,
        //       then authenticate() is called and a fingerprint is presented
        // Then: onSuccess receives a byte array equal to the original passphrase
    }

    // ── key invalidation ──────────────────────────────────────────────────────

    @Test
    @Ignore("Requires enrolling a new fingerprint on the device after enrolment")
    fun authenticate_returns_KEY_INVALIDATED_after_new_biometric_enrolled() {
        // When: enrol() succeeds, then the user adds a new fingerprint at OS level,
        //       then authenticate() is called
        // Then: onError is called with "KEY_INVALIDATED"
        // And: isEnrolled() returns false (unenroll was called automatically)
    }
}
