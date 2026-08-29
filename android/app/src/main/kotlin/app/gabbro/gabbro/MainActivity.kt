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

class MainActivity : GabbroUnlockHostActivity() {

    private companion object {
        const val EXPORT_CHANNEL = "app.gabbro.gabbro/export"
        const val APP_PASSKEYS_CHANNEL = "app.gabbro.gabbro/app_passkeys"
    }

    private var pendingDirPickResult: MethodChannel.Result? = null
    private lateinit var openTreeLauncher: ActivityResultLauncher<Uri?>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        purgeLegacyRecentApps(applicationContext)

        // The grant is scoped to the picked folder, so no manifest storage
        // permission; persisted so later exports skip the picker.
        openTreeLauncher =
            registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
                val result = pendingDirPickResult
                pendingDirPickResult = null
                if (uri == null) {
                    result?.success(null)
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
        super.configureFlutterEngine(flutterEngine)

        // The Flutter-less credential provider reads the F1 toggle from
        // SharedPreferences, so Dart mirrors it there.
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
                    // Read off the main thread, answered on it as Flutter requires.
                    "read_tree_file" -> {
                        val treeUri = call.argument<String>("treeUri")
                        val name = call.argument<String>("name")
                        if (treeUri == null || name == null) {
                            result.error("BAD_ARGS", "treeUri and name required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            val outcome = runCatching {
                                val dir = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
                                GabbroPicker.cacheTreeChild(cacheDir, name) { child ->
                                    dir?.findFile(child)?.uri?.let { contentResolver.openInputStream(it) }
                                }
                            }
                            runOnUiThread {
                                outcome.fold(
                                    { result.success(it) },
                                    { result.error("TREE_READ_FAILED", it.message, null) },
                                )
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Overwrites an existing child in place so a sync client sees the same
    // document with new content; creating over an existing name would trip
    // SAF's "(1)" de-duplication and break a fixed-name sync target.
    private fun writeViaSaf(treeUri: Uri, filename: String, data: ByteArray) {
        val dir = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IllegalStateException("Cannot open export folder")
        if (!dir.canWrite()) {
            throw IllegalStateException("No write permission for the export folder")
        }
        val target = dir.findFile(filename)
            ?: dir.createFile("application/octet-stream", filename)
            ?: throw IllegalStateException("Cannot create $filename")
        // "wt" truncates, so an overwrite leaves no tail of the old content.
        contentResolver.openOutputStream(target.uri, "wt")?.use { it.write(data) }
            ?: throw IllegalStateException("Cannot open $filename for writing")
    }
}

internal const val LEGACY_RECENT_APPS_PREFS = "gabbro_recent_autofill_apps"

/**
 * Nothing reads this store any more; without the purge it would list the
 * apps the user logged into, on disk, forever. A free function because a
 * FlutterActivity cannot run under Robolectric. Remove at v1.0.
 */
internal fun purgeLegacyRecentApps(context: Context) {
    context.deleteSharedPreferences(LEGACY_RECENT_APPS_PREFS)
}
