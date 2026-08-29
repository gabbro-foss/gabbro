package app.gabbro.gabbro

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Launched by [GabbroAutofillService.onSaveRequest]. Matching happens here
 * (the one source of truth); Dart performs the write so it follows the
 * in-app `passwordHistoryExpiry`.
 */
class SaveActivity : GabbroUnlockHostActivity() {

    companion object {
        private const val CHANNEL = "app.gabbro.gabbro/autofill_save"
        const val EXTRA_USERNAME = "app.gabbro.gabbro.SAVE_USERNAME"
        const val EXTRA_EMAIL = "app.gabbro.gabbro.SAVE_EMAIL"
        const val EXTRA_PASSWORD = "app.gabbro.gabbro.SAVE_PASSWORD"
        const val EXTRA_URL = "app.gabbro.gabbro.SAVE_URL"
        const val EXTRA_APP_ID = "app.gabbro.gabbro.SAVE_APP_ID"
    }

    private val publicSuffixList: PublicSuffixList by lazy { PublicSuffixList.fromAsset(this) }

    override fun getDartEntrypointFunctionName(): String = "autofillSaveMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isUnlocked" -> result.success(RustBridge.isVaultUnlocked())
                    "getSaveContext" -> result.success(buildSaveContext())
                    // Launched in its own task (FLAG_ACTIVITY_NEW_TASK); a bare
                    // finish() would leave it behind and re-focusing Gabbro
                    // would resurface this screen.
                    "done" -> {
                        setResult(RESULT_OK)
                        finishAndRemoveTask()
                        result.success(null)
                    }
                    "cancel" -> {
                        setResult(RESULT_CANCELED)
                        finishAndRemoveTask()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Password-free summaries; only the one matched entry is decrypted. */
    private fun buildSaveContext(): String {
        val captured = CapturedLogin(
            username = intent?.getStringExtra(EXTRA_USERNAME).orEmpty(),
            email = intent?.getStringExtra(EXTRA_EMAIL).orEmpty(),
            password = intent?.getStringExtra(EXTRA_PASSWORD).orEmpty(),
        )
        val url = intent?.getStringExtra(EXTRA_URL).orEmpty()
        val appId = intent?.getStringExtra(EXTRA_APP_ID).orEmpty()
        val webDomain = url.ifBlank { null }
        val pkg = appId.ifBlank { null }

        val summaries = parseSummariesJson(RustBridge.listLoginSummaries())
        val candidates = matchingCredentials(summaries, webDomain, pkg, publicSuffixList)
        val matched = matchSaveTarget(captured, summaries, webDomain, pkg, publicSuffixList)
        val decision = if (matched == null) {
            SaveDecision.Create
        } else {
            decideSave(matched.id, fetchPassword(matched.id), captured.password)
        }
        return saveContextJson(captured, url, appId, decision, candidates)
    }
}
