package app.gabbro.gabbro

import android.app.PendingIntent
import android.content.Intent
import android.nfc.NfcAdapter
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import com.yubico.yubikit.core.YubiKeyConnection
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * GabbroUnlockHostActivity — shared base for every activity that hosts the
 * unlock UI: the main app ([MainActivity]) and the autofill auth wall
 * ([UnlockActivity]).
 *
 * It provides the parts both need so they cannot drift apart:
 *  - the `…/yubikey` MethodChannel (register / unlock taps, USB + NFC), bounded
 *    and cancellable via [TapFlow];
 *  - the `…/biometric` MethodChannel (BiometricPrompt — needs a FragmentActivity);
 *  - YubiKey NDEF/OTP suppression: foreground dispatch on resume, and re-arming it
 *    after NFC reader mode stops so a stray OTP-URL tap routes to onNewIntent
 *    instead of opening the browser (demo.yubico.com).
 *  - FLAG_SECURE (no screenshots / no recents thumbnail) on the unlock surface.
 *
 * Subclasses override [configureFlutterEngine], call `super` first (registers the
 * shared channels), then add their own channels on the same engine.
 */
abstract class GabbroUnlockHostActivity : FlutterFragmentActivity() {

    companion object {
        private const val CHANNEL = "app.gabbro.gabbro/yubikey"
        private const val BIOMETRIC_CHANNEL = "app.gabbro.gabbro/biometric"

        // A YubiKey tap blocks until a key is presented; bound the wait so a
        // stalled tap (no key) cannot strand the UI on an endless spinner.
        private const val TAP_TIMEOUT_MS = 30_000L
    }

    private var nfcAdapter: NfcAdapter? = null

    // In-flight YubiKey tap state machine (shared, testable). Arms USB/NFC
    // discovery, retries once on a transient error, bounds the flow with a
    // timeout, and is abortable via cancel_tap.
    private val tapHandler = Handler(Looper.getMainLooper())
    private val tapFlow: TapFlow by lazy {
        TapFlow(
            handler = tapHandler,
            timeoutMs = TAP_TIMEOUT_MS,
            startDiscovery = { transport, onConnected, onError ->
                startDiscovery(transport, onConnected, onError)
            },
            stopDiscovery = { transport -> stopDiscovery(transport) },
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    // Suppress the YubiKey NDEF URL from opening the browser while the unlock
    // surface is in the foreground. When yubikit's reader mode is active it takes
    // priority; when it is stopped (after a CTAP2 op) foreground dispatch routes
    // NDEF intents to onNewIntent instead of the browser.
    override fun onResume() {
        super.onResume()
        val adapter = NfcAdapter.getDefaultAdapter(this) ?: return
        nfcAdapter = adapter
        adapter.enableForegroundDispatch(this, foregroundDispatchIntent(), null, null)
    }

    override fun onPause() {
        super.onPause()
        nfcAdapter?.disableForegroundDispatch(this)
    }

    // NFC intents (NDEF) are delivered here via foreground dispatch.
    // Calling super is enough — no browser launch occurs because we don't
    // forward the tag URI.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerBiometricChannel(flutterEngine)
        registerYubikeyChannel(flutterEngine)
    }

    private fun registerBiometricChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BIOMETRIC_CHANNEL)
            .setMethodCallHandler { call, result ->
                val title = call.argument<String>("title")
                    ?: applicationInfo.loadLabel(packageManager).toString()
                val subtitle = call.argument<String>("subtitle") ?: ""
                val vaultPath = call.argument<String>("vaultPath") ?: ""
                when (call.method) {
                    "isAvailable" ->
                        result.success(BiometricHelper.isAvailable(this))
                    "isEnrolled" ->
                        result.success(BiometricHelper.isEnrolled(this, vaultPath))
                    "enroll" -> {
                        val passphraseHex = call.argument<String>("passphrase")
                        if (passphraseHex == null) {
                            result.error("BAD_ARGS", "passphrase required", null)
                            return@setMethodCallHandler
                        }
                        val passphrase = passphraseHex.fromHex()
                        BiometricHelper.enroll(
                            activity = this,
                            vaultPath = vaultPath,
                            passphrase = passphrase,
                            promptTitle = title,
                            promptSubtitle = subtitle,
                            onSuccess = { result.success(null) },
                            onError = { msg -> result.error("BIOMETRIC_ERROR", msg, null) },
                        )
                    }
                    "authenticate" ->
                        BiometricHelper.authenticate(
                            activity = this,
                            vaultPath = vaultPath,
                            promptTitle = title,
                            promptSubtitle = subtitle,
                            onSuccess = { passphrase ->
                                result.success(passphrase)
                                passphrase.fill(0)
                            },
                            onError = { msg ->
                                val code = if (msg == "KEY_INVALIDATED") "BIOMETRIC_INVALIDATED"
                                           else "BIOMETRIC_ERROR"
                                result.error(code, msg, null)
                            },
                        )
                    "unenroll" -> {
                        BiometricHelper.unenroll(this, vaultPath)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerYubikeyChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val pin = call.argument<String>("pin")?.toCharArray()
                val transport = call.argument<String>("transport") ?: "usb"
                when (call.method) {
                    "register" -> {
                        tapFlow.run(result, transport, "REGISTER_FAILED") { conn, onOk, onErr ->
                            YubiKeyManager.register(
                                conn, pin,
                                onSuccess = { credId -> onOk(credId.toHex()) },
                                onError = onErr,
                            )
                        }
                    }
                    "get_hmac_secret" -> {
                        val credIdHex = call.argument<String>("credentialId")
                        if (credIdHex == null) {
                            result.error("BAD_ARGS", "credentialId required", null)
                            return@setMethodCallHandler
                        }
                        val saltHex = call.argument<String>("salt")
                        if (saltHex == null) {
                            result.error("BAD_ARGS", "salt required", null)
                            return@setMethodCallHandler
                        }
                        tapFlow.run(result, transport, "HMAC_FAILED") { conn, onOk, onErr ->
                            YubiKeyManager.getHmacSecret(
                                conn, credIdHex.fromHex(), saltHex.fromHex(), pin,
                                onSuccess = { secret -> onOk(secret.toHex()) },
                                onError = onErr,
                            )
                        }
                    }
                    "get_hmac_secret_multi" -> {
                        val rawRecords = call.argument<List<Map<String, Any>>>("records")
                        if (rawRecords.isNullOrEmpty()) {
                            result.error("BAD_ARGS", "records required", null)
                            return@setMethodCallHandler
                        }
                        val records = rawRecords.map { r ->
                            Pair(
                                (r["credentialId"] as String).fromHex(),
                                (r["salt"] as String).fromHex(),
                            )
                        }
                        tapFlow.run(result, transport, "HMAC_MULTI_FAILED") { conn, onOk, onErr ->
                            YubiKeyManager.getHmacSecretAny(
                                conn, records, pin,
                                onSuccess = { hmac, credentialId ->
                                    onOk(mapOf(
                                        "hmac" to hmac.toHex(),
                                        "credentialId" to credentialId.toHex(),
                                    ))
                                },
                                onError = onErr,
                            )
                        }
                    }
                    "cancel_tap" -> {
                        tapFlow.cancel()
                        result.success(null)
                    }
                    "has_nfc" -> {
                        // Hardware presence (not enabled-state): drives whether the
                        // UI offers the NFC transport at all. Null adapter = no NFC.
                        result.success(NfcAdapter.getDefaultAdapter(this) != null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startDiscovery(
        transport: String,
        onConnected: (YubiKeyConnection) -> Unit,
        onError: (String) -> Unit,
    ) = when (transport) {
        "nfc" -> YubiKeyManager.startNfcDiscovery(this, onConnected, onError)
        else  -> YubiKeyManager.startUsbDiscovery(this, onConnected, onError)
    }

    private fun stopDiscovery(transport: String) = when (transport) {
        "nfc" -> {
            YubiKeyManager.stopNfcDiscovery(this)
            // Reader mode is now off; re-arm foreground dispatch so any stray NDEF
            // intents (OTP URL still on key) route to onNewIntent, not the browser.
            nfcAdapter?.enableForegroundDispatch(this, foregroundDispatchIntent(), null, null)
        }
        else -> YubiKeyManager.stopUsbDiscovery()
    }

    private fun foregroundDispatchIntent(): PendingIntent {
        val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getActivity(
            this, 0,
            Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            flags,
        )
    }

    protected fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    protected fun String.fromHex(): ByteArray {
        check(length % 2 == 0) { "Hex string must have even length" }
        return ByteArray(length / 2) { i -> substring(i * 2, i * 2 + 2).toInt(16).toByte() }
    }
}
