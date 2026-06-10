package app.gabbro.gabbro

import android.app.PendingIntent
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.nfc.NfcAdapter
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import com.yubico.yubikit.core.YubiKeyConnection
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private companion object {
        const val CHANNEL = "app.gabbro.gabbro/yubikey"
        const val BIOMETRIC_CHANNEL = "app.gabbro.gabbro/biometric"
        const val EXPORT_CHANNEL = "app.gabbro.gabbro/export"
    }

    private var nfcAdapter: NfcAdapter? = null

    // SAF directory picker: the result arrives asynchronously, so we stash the
    // pending Flutter result and complete it in the launcher callback.
    private var pendingDirPickResult: MethodChannel.Result? = null
    private lateinit var openTreeLauncher: ActivityResultLauncher<Uri?>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)

        // ACTION_OPEN_DOCUMENT_TREE picker for choosing the export folder. The
        // grant is scoped to exactly the folder the user picks — no manifest
        // storage permission. We persist it so future exports skip the picker.
        openTreeLauncher =
            registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
                val result = pendingDirPickResult
                pendingDirPickResult = null
                if (uri == null) {
                    result?.success(null) // user cancelled the picker
                    return@registerForActivityResult
                }
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                val name = DocumentFile.fromTreeUri(this, uri)?.name ?: ""
                result?.success(mapOf("treeUri" to uri.toString(), "displayName" to name))
            }
    }

    // Suppress the YubiKey NDEF URL from opening the browser while the app is
    // in the foreground. When yubikit's reader mode is active it takes
    // priority; when it is stopped (after a CTAP2 op) foreground dispatch
    // routes NDEF intents to onNewIntent instead of the browser.
    override fun onResume() {
        super.onResume()
        val adapter = NfcAdapter.getDefaultAdapter(this) ?: return
        nfcAdapter = adapter
        val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val pi = PendingIntent.getActivity(
            this, 0,
            Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            flags,
        )
        adapter.enableForegroundDispatch(this, pi, null, null)
    }

    override fun onPause() {
        super.onPause()
        nfcAdapter?.disableForegroundDispatch(this)
    }

    // NFC intents (NDEF) are delivered here via foreground dispatch.
    // Calling super is enough — Flutter routing is preserved for deep links,
    // and no browser launch occurs because we don't forward the tag URI.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                        BiometricHelper.unenroll(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXPORT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick_export_dir" -> {
                        pendingDirPickResult = result
                        openTreeLauncher.launch(null)
                    }
                    "has_grant" -> {
                        val treeUri = call.argument<String>("treeUri")
                        if (treeUri == null) {
                            result.error("BAD_ARGS", "treeUri required", null)
                            return@setMethodCallHandler
                        }
                        val held = contentResolver.persistedUriPermissions.any {
                            it.uri.toString() == treeUri && it.isWritePermission
                        }
                        result.success(held)
                    }
                    "write_export_file" -> {
                        val treeUri = call.argument<String>("treeUri")
                        val filename = call.argument<String>("filename")
                        val data = call.argument<ByteArray>("data")
                        val sha256Filename = call.argument<String>("sha256Filename")
                        val sha256Content = call.argument<String>("sha256Content")
                        if (treeUri == null || filename == null || data == null ||
                            sha256Filename == null || sha256Content == null
                        ) {
                            result.error("BAD_ARGS", "missing export arguments", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val tree = Uri.parse(treeUri)
                            writeViaSaf(tree, filename, data)
                            writeViaSaf(tree, sha256Filename, sha256Content.toByteArray())
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("EXPORT_WRITE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val pin = call.argument<String>("pin")?.toCharArray()
                val transport = call.argument<String>("transport") ?: "usb"
                when (call.method) {
                    "register_and_get_hmac" -> {
                        val saltHex = call.argument<String>("salt")
                        if (saltHex == null) {
                            result.error("BAD_ARGS", "salt required", null)
                            return@setMethodCallHandler
                        }
                        fun attempt(retriesLeft: Int) {
                            startDiscovery(
                                transport,
                                onConnected = { connection ->
                                    YubiKeyManager.registerAndGetHmac(
                                        connection, saltHex.fromHex(), pin,
                                        onSuccess = { credId, hmacSecret ->
                                            stopDiscovery(transport)
                                            result.success(mapOf(
                                                "credentialId" to credId.toHex(),
                                                "hmacSecret" to hmacSecret.toHex(),
                                            ))
                                        },
                                        onError = { msg ->
                                            stopDiscovery(transport)
                                            if (retriesLeft > 0) {
                                                android.os.Handler(android.os.Looper.getMainLooper())
                                                    .postDelayed({ attempt(retriesLeft - 1) }, 500)
                                            } else {
                                                result.error("REGISTER_HMAC_FAILED", msg, null)
                                            }
                                        },
                                    )
                                },
                                onError = { msg ->
                                    if (retriesLeft > 0) {
                                        android.os.Handler(android.os.Looper.getMainLooper())
                                            .postDelayed({ attempt(retriesLeft - 1) }, 500)
                                    } else {
                                        result.error("TRANSPORT_ERROR", msg, null)
                                    }
                                },
                            )
                        }
                        attempt(1)
                    }
                    "register" -> {
                        fun attempt(retriesLeft: Int) {
                            startDiscovery(
                                transport,
                                onConnected = { connection ->
                                    YubiKeyManager.register(
                                        connection, pin,
                                        onSuccess = { credId ->
                                            stopDiscovery(transport)
                                            result.success(credId.toHex())
                                        },
                                        onError = { msg ->
                                            stopDiscovery(transport)
                                            if (retriesLeft > 0) {
                                                android.os.Handler(android.os.Looper.getMainLooper())
                                                    .postDelayed({ attempt(retriesLeft - 1) }, 500)
                                            } else {
                                                result.error("REGISTER_FAILED", msg, null)
                                            }
                                        },
                                    )
                                },
                                onError = { msg ->
                                    if (retriesLeft > 0) {
                                        android.os.Handler(android.os.Looper.getMainLooper())
                                            .postDelayed({ attempt(retriesLeft - 1) }, 500)
                                    } else {
                                        result.error("TRANSPORT_ERROR", msg, null)
                                    }
                                },
                            )
                        }
                        attempt(1)
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
                        fun attempt(retriesLeft: Int) {
                            startDiscovery(
                                transport,
                                onConnected = { connection ->
                                    YubiKeyManager.getHmacSecret(
                                        connection, credIdHex.fromHex(), saltHex.fromHex(), pin,
                                        onSuccess = { secret ->
                                            stopDiscovery(transport)
                                            result.success(secret.toHex())
                                        },
                                        onError = { msg ->
                                            stopDiscovery(transport)
                                            if (retriesLeft > 0) {
                                                android.os.Handler(android.os.Looper.getMainLooper())
                                                    .postDelayed({ attempt(retriesLeft - 1) }, 500)
                                            } else {
                                                result.error("HMAC_FAILED", msg, null)
                                            }
                                        },
                                    )
                                },
                                onError = { msg ->
                                    if (retriesLeft > 0) {
                                        android.os.Handler(android.os.Looper.getMainLooper())
                                            .postDelayed({ attempt(retriesLeft - 1) }, 500)
                                    } else {
                                        result.error("TRANSPORT_ERROR", msg, null)
                                    }
                                },
                            )
                        }
                        attempt(1)
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
                        fun attempt(retriesLeft: Int) {
                            startDiscovery(
                                transport,
                                onConnected = { connection ->
                                    YubiKeyManager.getHmacSecretAny(
                                        connection, records, pin,
                                        onSuccess = { hmac, credentialId ->
                                            stopDiscovery(transport)
                                            result.success(mapOf(
                                                "hmac" to hmac.toHex(),
                                                "credentialId" to credentialId.toHex(),
                                            ))
                                        },
                                        onError = { msg ->
                                            stopDiscovery(transport)
                                            if (retriesLeft > 0) {
                                                android.os.Handler(android.os.Looper.getMainLooper())
                                                    .postDelayed({ attempt(retriesLeft - 1) }, 500)
                                            } else {
                                                result.error("HMAC_MULTI_FAILED", msg, null)
                                            }
                                        },
                                    )
                                },
                                onError = { msg ->
                                    if (retriesLeft > 0) {
                                        android.os.Handler(android.os.Looper.getMainLooper())
                                            .postDelayed({ attempt(retriesLeft - 1) }, 500)
                                    } else {
                                        result.error("TRANSPORT_ERROR", msg, null)
                                    }
                                },
                            )
                        }
                        attempt(1)
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
            nfcAdapter?.let { adapter ->
                val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                val pi = PendingIntent.getActivity(
                    this, 0,
                    Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    flags,
                )
                adapter.enableForegroundDispatch(this, pi, null, null)
            }
        }
        else -> YubiKeyManager.stopUsbDiscovery()
    }

    // Write `data` to `filename` inside the granted directory tree. Finds an
    // existing child by name and overwrites it in place (preserves the document, so
    // a sync client sees the same file with new content); only creates when absent.
    // Never blind-creates over an existing name — that would trip SAF's "(1)"
    // de-duplication and break a fixed-name sync target.
    private fun writeViaSaf(treeUri: Uri, filename: String, data: ByteArray) {
        val dir = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IllegalStateException("Cannot open export folder")
        if (!dir.canWrite()) {
            throw IllegalStateException("No write permission for the export folder")
        }
        val target = dir.findFile(filename)
            ?: dir.createFile("application/octet-stream", filename)
            ?: throw IllegalStateException("Cannot create $filename")
        // "wt" = write + truncate, so an overwrite fully replaces prior content.
        contentResolver.openOutputStream(target.uri, "wt")?.use { it.write(data) }
            ?: throw IllegalStateException("Cannot open $filename for writing")
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    private fun String.fromHex(): ByteArray {
        check(length % 2 == 0) { "Hex string must have even length" }
        return ByteArray(length / 2) { i -> substring(i * 2, i * 2 + 2).toInt(16).toByte() }
    }
}
