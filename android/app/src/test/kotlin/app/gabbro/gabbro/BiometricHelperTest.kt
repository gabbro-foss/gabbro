package app.gabbro.gabbro

import org.junit.Ignore
import org.junit.Test

class BiometricHelperTest {

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
    @Ignore("Requires Android runtime (SharedPreferences)")
    fun isEnrolled_returns_false_before_enrolment() {
        // When: no enrolment has been performed (SharedPreferences empty)
        // Then: isEnrolled() returns false
    }

    @Test
    @Ignore("Requires Android runtime (SharedPreferences)")
    fun isEnrolled_returns_true_after_successful_enrolment() {
        // When: enrol() completes successfully and stores ciphertext + IV
        // Then: isEnrolled() returns true
    }

    // ── unenroll ──────────────────────────────────────────────────────────────

    @Test
    @Ignore("Requires Android runtime (SharedPreferences + Keystore)")
    fun unenroll_clears_stored_ciphertext_and_iv() {
        // When: unenroll() is called after a successful enrolment
        // Then: SharedPreferences no longer contains ciphertext or IV keys
    }

    @Test
    @Ignore("Requires Android runtime (SharedPreferences + Keystore)")
    fun unenroll_deletes_keystore_key() {
        // When: unenroll() is called
        // Then: the KEY_ALIAS entry no longer exists in AndroidKeyStore
    }

    @Test
    @Ignore("Requires Android runtime (SharedPreferences)")
    fun unenroll_when_not_enrolled_does_not_throw() {
        // When: unenroll() is called with no prior enrolment
        // Then: no exception is thrown; isEnrolled() still returns false
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
