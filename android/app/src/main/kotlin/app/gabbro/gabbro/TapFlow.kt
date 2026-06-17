package app.gabbro.gabbro

import android.os.Handler
import com.yubico.yubikit.core.YubiKeyConnection
import io.flutter.plugin.common.MethodChannel

/**
 * TapFlow — the YubiKey tap state machine, lifted out of the host activity so it
 * is unit-testable and shared by every unlock host (main app + autofill).
 *
 * One tap operation (register or unlock) arms USB/NFC discovery and waits for a
 * connection callback. The whole flow is bounded by [timeoutMs] and abortable via
 * [cancel]. Exactly one of timeout / cancel / success / final-error completes the
 * Flutter result — all funnel through [finish], a no-op once the result is already
 * answered (first to fire wins). A transient transport/CTAP error retries once.
 *
 * [startDiscovery] / [stopDiscovery] are injected so the host supplies the real
 * transport wiring (and, for NFC, the foreground-dispatch re-arm) while the state
 * machine stays framework-light.
 */
class TapFlow(
    private val handler: Handler,
    private val timeoutMs: Long,
    private val startDiscovery: (
        transport: String,
        onConnected: (YubiKeyConnection) -> Unit,
        onError: (String) -> Unit,
    ) -> Unit,
    private val stopDiscovery: (transport: String) -> Unit,
) {
    private var timeoutRunnable: Runnable? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingTransport: String? = null

    /** Transport of the in-flight tap, or null if none is pending. */
    val activeTransport: String?
        get() = pendingTransport

    /**
     * Runs one tap operation. [invoke] performs the actual CTAP2 call once a
     * connection is up, reporting through `onOk` (success payload) / `onErr` (msg).
     */
    fun run(
        result: MethodChannel.Result,
        transport: String,
        errorCode: String,
        invoke: (
            connection: YubiKeyConnection,
            onOk: (Any?) -> Unit,
            onErr: (String) -> Unit,
        ) -> Unit,
    ) {
        pendingResult = result
        pendingTransport = transport
        armTimeout(transport)
        attempt(transport, errorCode, invoke, retriesLeft = 1)
    }

    /** Aborts an in-flight tap (e.g. the user pressed Cancel). */
    fun cancel() {
        pendingTransport?.let { t ->
            finish(t) { it.error("TAP_CANCELLED", "Tap cancelled by user", null) }
        }
    }

    private fun attempt(
        transport: String,
        errorCode: String,
        invoke: (YubiKeyConnection, (Any?) -> Unit, (String) -> Unit) -> Unit,
        retriesLeft: Int,
    ) {
        if (pendingResult == null) return // timed out / cancelled meanwhile
        startDiscovery(
            transport,
            { conn ->
                invoke(
                    conn,
                    { payload -> finish(transport) { it.success(payload) } },
                    { msg ->
                        stopDiscovery(transport)
                        if (retriesLeft > 0) {
                            handler.postDelayed(
                                { attempt(transport, errorCode, invoke, retriesLeft - 1) },
                                RETRY_DELAY_MS,
                            )
                        } else {
                            finish(transport) { it.error(errorCode, msg, null) }
                        }
                    },
                )
            },
            { msg ->
                if (retriesLeft > 0) {
                    handler.postDelayed(
                        { attempt(transport, errorCode, invoke, retriesLeft - 1) },
                        RETRY_DELAY_MS,
                    )
                } else {
                    finish(transport) { it.error("TRANSPORT_ERROR", msg, null) }
                }
            },
        )
    }

    private fun armTimeout(transport: String) {
        val r = Runnable {
            finish(transport) {
                it.error("TAP_TIMEOUT", "No YubiKey detected. Tap timed out.", null)
            }
        }
        timeoutRunnable = r
        handler.postDelayed(r, timeoutMs)
    }

    /** Complete the pending result once, stop discovery, clear timeout/state. */
    private fun finish(transport: String, complete: (MethodChannel.Result) -> Unit) {
        timeoutRunnable?.let { handler.removeCallbacks(it) }
        timeoutRunnable = null
        val r = pendingResult ?: return
        pendingResult = null
        pendingTransport = null
        stopDiscovery(transport)
        complete(r)
    }

    private companion object {
        const val RETRY_DELAY_MS = 500L
    }
}
