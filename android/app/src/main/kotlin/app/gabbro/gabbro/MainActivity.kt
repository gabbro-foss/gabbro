package app.gabbro.gabbro

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — the app's main Flutter surface. Inherits the shared unlock
 * plumbing (YubiKey + biometric channels, NFC NDEF suppression, FLAG_SECURE)
 * from [GabbroUnlockHostActivity] and adds the main-app-only channel: SAF export.
 */
class MainActivity : GabbroUnlockHostActivity() {

    private companion object {
        const val EXPORT_CHANNEL = "app.gabbro.gabbro/export"
        const val APP_PASSKEYS_CHANNEL = "app.gabbro.gabbro/app_passkeys"
    }

    // SAF directory picker: the result arrives asynchronously, so we stash the
    // pending Flutter result and complete it in the launcher callback.
    private var pendingDirPickResult: MethodChannel.Result? = null
    private lateinit var openTreeLauncher: ActivityResultLauncher<Uri?>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        purgeLegacyRecentApps(applicationContext)

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Registers the shared YubiKey + biometric channels and NFC suppression.
        super.configureFlutterEngine(flutterEngine)

        // Mirrors the Dart app-passkeys toggle (F1) into SharedPreferences,
        // where the Flutter-less credential provider reads it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_PASSKEYS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAppPasskeys" -> {
                        AppPasskeysStore.set(this, call.arguments as? Boolean ?: false)
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
}

/** SharedPreferences file of the removed autofill "recently used apps" store. */
internal const val LEGACY_RECENT_APPS_PREFS = "gabbro_recent_autofill_apps"

/**
 * Delete the leftover capture store on installs upgraded from a build that shipped
 * the app-id suggestion chips. It listed apps the user had tried to log into and
 * nothing reads it any more, so it would otherwise sit on disk forever. No-op once
 * absent. A free function because MainActivity is a FlutterActivity and cannot be
 * driven under Robolectric; nets in `LegacyPurgeTest`.
 *
 * Remove at v1.0 — no pre-1.0 install will still be around to upgrade.
 */
internal fun purgeLegacyRecentApps(context: Context) {
    context.deleteSharedPreferences(LEGACY_RECENT_APPS_PREFS)
}
