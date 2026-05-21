package app.gabbro.gabbro

import org.junit.Ignore
import org.junit.Test

class YubiKeyManagerTest {

    // ── Hardware (USB-C YubiKey 5C plugged into S23) ──────────────────────────────

    @Test
    @Ignore("Requires USB-C YubiKey 5C plugged into S23")
    fun register_returns_non_empty_credential_id() {
        // When: register() called with a live connection and PIN
        // Then: onSuccess fires with a non-empty credentialId ByteArray
    }

    @Test
    @Ignore("Requires registered credential on USB-C YubiKey 5C")
    fun getHmacSecret_returns_exactly_32_bytes() {
        // When: getHmacSecret() called with valid credentialId and 32-byte salt
        // Then: onSuccess fires with exactly 32 bytes
    }

    @Test
    @Ignore("Requires registered credential on USB-C YubiKey 5C")
    fun getHmacSecret_is_deterministic_for_same_salt() {
        // When: getHmacSecret() called twice with identical credentialId and salt
        // Then: both outputs are byte-for-byte equal
    }

    @Test
    @Ignore("Requires USB-C YubiKey 5C plugged into S23")
    fun registerAndGetHmac_returns_credential_id_and_32_byte_hmac_secret() {
        // When: registerAndGetHmac() called with a 32-byte salt and valid PIN
        // Then: onSuccess fires with non-empty credentialId and exactly 32-byte hmacSecret
    }

    // ── Hardware (NFC YubiKey 5 NFC tapped against S23) ──────────────────────────

    @Test
    @Ignore("Requires NFC YubiKey 5 NFC tapped against S23")
    fun nfc_register_returns_non_empty_credential_id() {
        // When: register() called via NFC connection with valid PIN
        // Then: onSuccess fires with a non-empty credentialId ByteArray
    }

    @Test
    @Ignore("Requires registered credential on NFC YubiKey 5 NFC")
    fun nfc_getHmacSecret_returns_exactly_32_bytes() {
        // When: getHmacSecret() called via NFC with valid credentialId and 32-byte salt
        // Then: onSuccess fires with exactly 32 bytes
    }

    @Test
    @Ignore("Requires registered credential on NFC YubiKey 5 NFC")
    fun nfc_getHmacSecret_is_deterministic_for_same_salt() {
        // When: getHmacSecret() called twice via NFC with identical credentialId and salt
        // Then: both outputs are byte-for-byte equal
    }

    @Test
    @Ignore("Requires NFC YubiKey 5 NFC tapped against S23")
    fun nfc_registerAndGetHmac_returns_credential_id_and_32_byte_hmac_secret() {
        // When: registerAndGetHmac() called via NFC with a 32-byte salt and valid PIN
        // Then: onSuccess fires with non-empty credentialId and exactly 32-byte hmacSecret
    }

    // ── Cross-transport (YubiKey 5 NFC USB-C: register on one transport, get HMAC on the other) ──

    @Test
    @Ignore("Requires YubiKey 5 NFC USB-C: plug in via USB-C, then tap via NFC")
    fun cross_usb_register_nfc_getHmac_returns_same_bytes() {
        // When: registerAndGetHmac() called via USB-C, then getHmacSecret() called via NFC
        //       with the same credentialId and salt
        // Then: both hmac-secret outputs are byte-for-byte equal
    }

    @Test
    @Ignore("Requires YubiKey 5 NFC USB-C: tap via NFC, then plug in via USB-C")
    fun cross_nfc_register_usb_getHmac_returns_same_bytes() {
        // When: registerAndGetHmac() called via NFC, then getHmacSecret() called via USB-C
        //       with the same credentialId and salt
        // Then: both hmac-secret outputs are byte-for-byte equal
    }
}
