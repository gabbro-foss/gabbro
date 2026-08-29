package app.gabbro.gabbro

import android.content.Intent
import android.os.Build
import android.service.autofill.FillResponse
import android.view.autofill.AutofillManager
import android.widget.RemoteViews
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The autofill authentication wall, opened by the IntentSender from
 * [GabbroAutofillService.buildAuthResponse]. Flutter unlocks the shared
 * session and calls "unlock" here; RESULT_OK is set only with a matched
 * credential, otherwise the OS delivers nothing to the field.
 */
class UnlockActivity : GabbroUnlockHostActivity() {

    companion object {
        private const val CHANNEL = "app.gabbro.gabbro/autofill"
        const val EXTRA_USERNAME_IDS = "app.gabbro.gabbro.EXTRA_USERNAME_IDS"
        const val EXTRA_EMAIL_IDS = "app.gabbro.gabbro.EXTRA_EMAIL_IDS"
        const val EXTRA_PASSWORD_IDS = "app.gabbro.gabbro.EXTRA_PASSWORD_IDS"
        const val EXTRA_WEB_DOMAIN = "app.gabbro.gabbro.EXTRA_WEB_DOMAIN"
        const val EXTRA_PACKAGE_NAME = "app.gabbro.gabbro.EXTRA_PACKAGE_NAME"
    }

    private val publicSuffixList: PublicSuffixList by lazy { PublicSuffixList.fromAsset(this) }

    override fun getDartEntrypointFunctionName(): String = "autofillUnlockMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "unlock" -> {
                        // Returns whether a credential matched so Dart shows the
                        // localized "no credentials" dialog; a native AlertDialog
                        // cannot use the Flutter ARBs.
                        //
                        // Must not finish here (RT-5): the Dart isolate dies with
                        // the activity, so Dart locks the session first and then
                        // calls "finish". Finishing now would race that lock.
                        val fillIntent = buildFillIntent()
                        if (fillIntent != null) {
                            setResult(RESULT_OK, fillIntent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "finish" -> {
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
     * The AutofillIds and context arrive as intent extras, so no
     * AssistStructure is needed. Multiple matches: first wins (a picker is
     * v2). Null when nothing matches.
     */
    private fun buildFillIntent(): Intent? {
        val usernameIds: ArrayList<android.view.autofill.AutofillId> =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent?.getParcelableArrayListExtra(EXTRA_USERNAME_IDS, android.view.autofill.AutofillId::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent?.getParcelableArrayListExtra(EXTRA_USERNAME_IDS)
            } ?: arrayListOf()

        val passwordIds: ArrayList<android.view.autofill.AutofillId> =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent?.getParcelableArrayListExtra(EXTRA_PASSWORD_IDS, android.view.autofill.AutofillId::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent?.getParcelableArrayListExtra(EXTRA_PASSWORD_IDS)
            } ?: arrayListOf()

        val emailIds: ArrayList<android.view.autofill.AutofillId> =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent?.getParcelableArrayListExtra(EXTRA_EMAIL_IDS, android.view.autofill.AutofillId::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent?.getParcelableArrayListExtra(EXTRA_EMAIL_IDS)
            } ?: arrayListOf()

        if (usernameIds.isEmpty() && emailIds.isEmpty() && passwordIds.isEmpty()) return null

        val webDomain = intent?.getStringExtra(EXTRA_WEB_DOMAIN)
        val appPackageName = intent?.getStringExtra(EXTRA_PACKAGE_NAME)

        val summariesJson = RustBridge.listLoginSummaries()
        val matches = matchingCredentials(
            parseSummariesJson(summariesJson),
            webDomain,
            appPackageName,
            publicSuffixList,
        )

        if (matches.isEmpty()) return null

        // Only the chosen entry's password is decrypted, never the whole vault.
        val cred = matches.first().let { it.copy(password = fetchPassword(it.id)) }
        val presentation = RemoteViews(packageName, R.layout.autofill_unlock_item)
        val dataset = buildFillDataset(usernameIds, emailIds, passwordIds, cred, presentation)

        val fillResponse = FillResponse.Builder()
            .addDataset(dataset)
            .build()

        return Intent().apply {
            putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, fillResponse)
        }
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        setResult(RESULT_CANCELED)
        finish()
    }
}
