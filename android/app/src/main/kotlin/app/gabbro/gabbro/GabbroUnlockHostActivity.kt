package app.gabbro.gabbro

import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.nfc.NfcAdapter
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.view.WindowManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import com.yubico.yubikit.core.YubiKeyConnection
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Shared base for [MainActivity] and [UnlockActivity], so YubiKey, biometric,
 * NDEF suppression and FLAG_SECURE cannot drift between them.
 * FlutterFragmentActivity because BiometricPrompt needs a FragmentActivity.
 * Subclasses call `super.configureFlutterEngine` first, then add channels.
 */
abstract class GabbroUnlockHostActivity : FlutterFragmentActivity() {

    companion object {
        private const val CHANNEL = "app.gabbro.gabbro/yubikey"
        private const val BIOMETRIC_CHANNEL = "app.gabbro.gabbro/biometric"

        // A tap blocks until a key is presented; unbounded, a missing key
        // would strand the UI on a spinner.
        private const val TAP_TIMEOUT_MS = 30_000L
    }

    private var nfcAdapter: NfcAdapter? = null

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

    // The dialog result arrives asynchronously; the Flutter result is completed
    // in the launcher callback.
    private var pendingFilePick: MethodChannel.Result? = null
    private var pendingPickWantsBytes = false
    private var pendingFolderPick: MethodChannel.Result? = null
    private lateinit var openFileLauncher: ActivityResultLauncher<GabbroPicker.PickRequest>
    private lateinit var openFolderLauncher: ActivityResultLauncher<Uri?>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)

        openFileLauncher =
            registerForActivityResult(GabbroPicker.OpenDocumentAt()) { uri ->
                val result = pendingFilePick
                pendingFilePick = null
                if (uri == null) {
                    result?.success(null)
                    return@registerForActivityResult
                }
                deliverPickedFile(uri, pendingPickWantsBytes, result)
            }

        openFolderLauncher =
            registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
                val result = pendingFolderPick
                pendingFolderPick = null
                if (uri == null) {
                    result?.success(null)
                    return@registerForActivityResult
                }
                result?.success(
                    GabbroPicker.rawPathFromDocumentId(
                        DocumentsContract.getTreeDocumentId(uri),
                    ),
                )
            }
    }

    /**
     * Reads off the main thread (a large attachment would freeze the UI) and
     * answers on it, as Flutter requires.
     */
    private fun deliverPickedFile(
        uri: Uri,
        wantsBytes: Boolean,
        result: MethodChannel.Result?,
    ) {
        val name = pickedFileName(uri)
        Thread {
            val reply = try {
                val stream = contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("Cannot read the picked file")
                if (wantsBytes) {
                    val bytes = stream.use { it.readBytes() }
                    Result.success<Any?>(mapOf("name" to name, "bytes" to bytes))
                } else {
                    val target = GabbroPicker.cacheTarget(cacheDir, name)
                    GabbroPicker.copyTo(stream, target)
                    Result.success<Any?>(GabbroPicker.pickedFileReply(target.absolutePath, uri))
                }
            } catch (e: Exception) {
                Result.failure<Any?>(e)
            }
            Handler(Looper.getMainLooper()).post {
                reply.fold(
                    onSuccess = { result?.success(it) },
                    onFailure = { result?.error("PICK_FAILED", it.message, null) },
                )
            }
        }.start()
    }

    private fun pickedFileName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
            }

    // Foreground dispatch routes a YubiKey's NDEF OTP URL to onNewIntent
    // instead of the browser. Reader mode takes priority while it is active.
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

    // The NDEF intent lands here; not forwarding the tag URI is what keeps
    // the browser closed.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerBiometricChannel(flutterEngine)
        registerYubikeyChannel(flutterEngine)
        registerPathsChannel(flutterEngine)
        registerPickerChannel(flutterEngine)
        registerUrlChannel(flutterEngine)
    }

    // On the base because the unlock surface shows URL dialogs (the
    // vault-upgrade link) and the autofill prompts reuse it.
    private fun registerUrlChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GabbroUrl.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open_url" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("BAD_ARGS", "url required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            startActivity(GabbroUrl.viewIntent(url))
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            // Dart reports it, so the tap does not look inert.
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // On the base so the autofill unlock screen can restore from a backup too.
    private fun registerPickerChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GabbroPicker.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick_file" -> {
                        pendingFilePick = result
                        pendingPickWantsBytes = false
                        openFileLauncher.launch(
                            GabbroPicker.PickRequest(
                                GabbroPicker.mimeTypes(call.argument<List<String>>("extensions")),
                                call.argument<String>("initial_uri"),
                            ),
                        )
                    }
                    "pick_file_bytes" -> {
                        pendingFilePick = result
                        pendingPickWantsBytes = true
                        openFileLauncher.launch(GabbroPicker.PickRequest(GabbroPicker.mimeTypes(null), null))
                    }
                    "pick_dir" -> {
                        pendingFolderPick = result
                        openFolderLauncher.launch(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerPathsChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AppPaths.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppSupportDir" -> result.success(AppPaths.appSupportDir(this))
                    else -> result.notImplemented()
                }
            }
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
                        // Hardware presence, not enabled state: decides whether
                        // the UI offers NFC at all.
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
            // Reader mode off: re-arm dispatch so a stray OTP URL stays out of
            // the browser.
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
