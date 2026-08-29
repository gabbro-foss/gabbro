package app.gabbro.gabbro

import android.os.Handler
import com.yubico.yubikit.core.YubiKeyConnection
import io.flutter.plugin.common.MethodChannel

/**
 * Exactly one of timeout, cancel, success or final error completes the
 * Flutter result: all funnel through [finish], first to fire wins. Discovery
 * is injected so the host owns the transport wiring and this stays testable.
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

    val activeTransport: String?
        get() = pendingTransport

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
        if (pendingResult == null) return
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
