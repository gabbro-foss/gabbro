package app.gabbro.gabbro

import android.os.Handler
import android.os.Looper
import com.yubico.yubikit.core.YubiKeyConnection
import io.flutter.plugin.common.MethodChannel
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/**
 * Robolectric tests for the shared YubiKey tap state machine. Pins the
 * invariants the host activities (main app + autofill) rely on: exactly one of
 * success / error / timeout / cancel completes the Flutter result, a transient
 * error retries once, and discovery is dispatched to the requested transport.
 */
@RunWith(RobolectricTestRunner::class)
class TapFlowTest {

    // Counting fake of MethodChannel.Result — records exactly what the flow returned.
    private class FakeResult : MethodChannel.Result {
        var successCount = 0
        var errorCount = 0
        var notImplementedCount = 0
        var lastSuccess: Any? = null
        var lastErrorCode: String? = null
        override fun success(result: Any?) { successCount++; lastSuccess = result }
        override fun error(code: String, message: String?, details: Any?) {
            errorCount++; lastErrorCode = code
        }
        override fun notImplemented() { notImplementedCount++ }
        val completions: Int get() = successCount + errorCount + notImplementedCount
    }

    private val fakeConn = object : YubiKeyConnection { override fun close() {} }

    // Captures the discovery callbacks so a test can drive connect/error, and
    // records the transports discovery was started/stopped with.
    private class FakeDiscovery {
        var onConnected: ((YubiKeyConnection) -> Unit)? = null
        var onError: ((String) -> Unit)? = null
        val started = mutableListOf<String>()
        val stopped = mutableListOf<String>()
    }

    private fun newFlow(disc: FakeDiscovery, timeoutMs: Long = 30_000L) = TapFlow(
        handler = Handler(Looper.getMainLooper()),
        timeoutMs = timeoutMs,
        startDiscovery = { transport, onConnected, onError ->
            disc.started.add(transport)
            disc.onConnected = onConnected
            disc.onError = onError
        },
        stopDiscovery = { transport -> disc.stopped.add(transport) },
    )

    private fun drainRetry() =
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(600))

    @Test
    fun success_completes_once_with_payload_and_stops_discovery() {
        val disc = FakeDiscovery()
        val flow = newFlow(disc)
        val result = FakeResult()

        flow.run(result, "usb", "FAILED") { _, onOk, _ -> onOk("payload") }
        disc.onConnected!!(fakeConn)

        assertEquals(1, result.successCount)
        assertEquals("payload", result.lastSuccess)
        assertEquals(1, result.completions)
        assertTrue(disc.stopped.contains("usb"))
        assertNull(flow.activeTransport)
    }

    @Test
    fun ctap_error_retries_once_then_succeeds() {
        val disc = FakeDiscovery()
        val flow = newFlow(disc)
        val result = FakeResult()
        var attempts = 0

        flow.run(result, "usb", "FAILED") { _, onOk, onErr ->
            attempts++
            if (attempts == 1) onErr("transient") else onOk("ok")
        }
        disc.onConnected!!(fakeConn) // attempt 1 -> onErr -> schedule retry
        drainRetry()
        disc.onConnected!!(fakeConn) // attempt 2 -> onOk

        assertEquals(1, result.successCount)
        assertEquals("ok", result.lastSuccess)
        assertEquals(1, result.completions)
    }

    @Test
    fun ctap_error_without_retry_reports_the_error_code() {
        val disc = FakeDiscovery()
        val flow = newFlow(disc)
        val result = FakeResult()

        flow.run(result, "usb", "MY_ERR") { _, _, onErr -> onErr("boom") }
        disc.onConnected!!(fakeConn) // attempt 1 -> onErr -> retry
        drainRetry()
        disc.onConnected!!(fakeConn) // attempt 2 -> onErr -> final error

        assertEquals(1, result.errorCount)
        assertEquals("MY_ERR", result.lastErrorCode)
    }

    @Test
    fun discovery_transport_error_reports_transport_error() {
        val disc = FakeDiscovery()
        val flow = newFlow(disc)
        val result = FakeResult()

        flow.run(result, "usb", "FAILED") { _, onOk, _ -> onOk("x") }
        disc.onError!!("usb fail") // attempt 1 discovery error -> retry
        drainRetry()
        disc.onError!!("usb fail") // attempt 2 -> TRANSPORT_ERROR

        assertEquals(1, result.errorCount)
        assertEquals("TRANSPORT_ERROR", result.lastErrorCode)
    }

    @Test
    fun timeout_reports_tap_timeout_and_stops_discovery() {
        val disc = FakeDiscovery()
        val flow = newFlow(disc, timeoutMs = 100L)
        val result = FakeResult()

        flow.run(result, "nfc", "FAILED") { _, _, _ -> }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(150))

        assertEquals(1, result.errorCount)
        assertEquals("TAP_TIMEOUT", result.lastErrorCode)
        assertTrue(disc.stopped.contains("nfc"))
        assertNull(flow.activeTransport)
    }

    @Test
    fun cancel_reports_tap_cancelled() {
        val disc = FakeDiscovery()
        val flow = newFlow(disc)
        val result = FakeResult()

        flow.run(result, "usb", "FAILED") { _, _, _ -> }
        flow.cancel()

        assertEquals(1, result.errorCount)
        assertEquals("TAP_CANCELLED", result.lastErrorCode)
    }

    @Test
    fun late_timeout_after_success_does_not_double_complete() {
        val disc = FakeDiscovery()
        val flow = newFlow(disc, timeoutMs = 100L)
        val result = FakeResult()

        flow.run(result, "usb", "FAILED") { _, onOk, _ -> onOk("done") }
        disc.onConnected!!(fakeConn)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(200))

        assertEquals(1, result.completions) // the timeout must not fire a 2nd completion
    }

    @Test
    fun dispatches_discovery_to_the_requested_transport() {
        val disc = FakeDiscovery()
        val flow = newFlow(disc)

        flow.run(FakeResult(), "nfc", "FAILED") { _, _, _ -> }

        assertEquals(listOf("nfc"), disc.started)
    }
}
