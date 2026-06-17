package app.gabbro.gabbro

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * SaveActivity — the autofill SAVE counterpart to [UnlockActivity].
 *
 * Launched by [GabbroAutofillService.onSaveRequest] after the user submits a login
 * the vault lacks (or a changed password). A [GabbroUnlockHostActivity] subclass, so
 * it inherits the YubiKey + biometric channels, NFC NDEF suppression, and FLAG_SECURE.
 *
 * Flow:
 *   1. Runs the `autofillSaveMain` Flutter entrypoint. If the vault is locked the
 *      reused UnlockScreen unlocks it; if already unlocked it goes straight to the
 *      SaveConfirmScreen.
 *   2. Dart calls `getSaveContext` (post-unlock); we match the captured login against
 *      the session here — the single source of truth — and return the suggested action
 *      + same-site candidates.
 *   3. Dart performs the write (create/update) so it follows the in-app
 *      `passwordHistoryExpiry`, then calls `done` (or `cancel`); we finish.
 *
 * The captured login + web/app context arrive as intent extras from onSaveRequest.
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

    // Backs eTLD+1 matching — the same vendored list the autofill service loads.
    private val publicSuffixList: PublicSuffixList by lazy { PublicSuffixList.fromAsset(this) }

    override fun getDartEntrypointFunctionName(): String = "autofillSaveMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Registers the shared YubiKey + biometric channels and NFC suppression.
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isUnlocked" -> result.success(RustBridge.isVaultUnlocked())
                    "getSaveContext" -> result.success(buildSaveContext())
                    "done" -> {
                        setResult(RESULT_OK)
                        finish()
                        result.success(null)
                    }
                    "cancel" -> {
                        setResult(RESULT_CANCELED)
                        finish()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Builds the `/autofill_save` payload: matches the captured login (intent extras)
     * against the unlocked session and serialises the suggested [SaveDecision] plus the
     * same-site candidates for the "choose another" picker. Runs post-unlock; matching
     * uses password-free summaries and decrypts only the one identifier-matched entry.
     */
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
