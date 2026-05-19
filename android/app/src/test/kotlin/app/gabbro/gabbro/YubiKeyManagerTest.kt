package app.gabbro.gabbro

import com.yubico.yubikit.fido.client.ClientError
import org.junit.Assert.assertTrue
import org.junit.Ignore
import org.junit.Test

class YubiKeyManagerTest {

    // ── Live (no hardware) ────────────────────────────────────────────────────────

    @Test
    fun describeClientError_device_ineligible_is_meaningful() {
        val e = ClientError(ClientError.Code.DEVICE_INELIGIBLE, "test")
        val msg = YubiKeyManager.describeClientError(e)
        assertTrue("Expected 'eligible' in message, got: $msg", msg.contains("eligible"))
    }

    @Test
    fun describeClientError_timeout_is_meaningful() {
        val e = ClientError(ClientError.Code.TIMEOUT, "test")
        val msg = YubiKeyManager.describeClientError(e)
        assertTrue("Expected 'timed out' in message, got: $msg", msg.contains("timed out"))
    }

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
}
