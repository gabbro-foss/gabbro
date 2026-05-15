package app.gabbro.gabbro

import android.content.Intent
import android.view.WindowManager
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.service.autofill.FillResponse
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * UnlockActivity — the autofill authentication wall.
 *
 * Launched by the OS when GabbroAutofillService returns a Dataset with an
 * IntentSender (i.e. the vault is locked and a fill request has arrived).
 *
 * Flow:
 *   1. OS launches this activity via the IntentSender from buildAuthResponse().
 *   2. We show the Flutter /autofill-unlock route (passphrase entry).
 *   3a. User unlocks successfully → Flutter calls back into Kotlin via a
 *       MethodChannel (wired in a later session), we build a FillResponse
 *       with the requested credential and finish with RESULT_OK.
 *   3b. User cancels / back-presses → finish with RESULT_CANCELED.
 *       The OS delivers nothing to the target field.
 *
 * This activity must never finish with RESULT_OK unless the vault is
 * confirmed unlocked and a valid credential has been selected.
 */
class UnlockActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "app.gabbro.gabbro/autofill"
        const val EXTRA_USERNAME_IDS = "app.gabbro.gabbro.EXTRA_USERNAME_IDS"
        const val EXTRA_PASSWORD_IDS = "app.gabbro.gabbro.EXTRA_PASSWORD_IDS"
        const val EXTRA_WEB_DOMAIN = "app.gabbro.gabbro.EXTRA_WEB_DOMAIN"
        const val EXTRA_PACKAGE_NAME = "app.gabbro.gabbro.EXTRA_PACKAGE_NAME"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun getDartEntrypointFunctionName(): String = "autofillUnlockMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "unlock" -> {
                        val fillIntent = buildFillIntent()
                        if (fillIntent != null) {
                            setResult(RESULT_OK, fillIntent)
                            finish()
                        } else {
                            // No matching credentials — show a dismissible
                            // dialog explaining why, then cancel.
                            val appPackageName = intent?.getStringExtra(EXTRA_PACKAGE_NAME)
                            val token = appPackageName?.let { extractAppToken(it) } ?: appPackageName ?: "unknown"
                            android.app.AlertDialog.Builder(this)
                                .setTitle("No credentials found")
                                .setMessage("No Gabbro credentials match this app ($token). If you trust it, copy/paste your credentials manually. Note: the app identifier may differ from its display name.")
                                .setPositiveButton("Dismiss") { _, _ ->
                                    setResult(RESULT_CANCELED)
                                    finish()
                                }
                                .setCancelable(false)
                                .show()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Runs domain/package matching after unlock and builds a FillResponse.
     *
     * GabbroAutofillService passes the parsed AutofillIds, web domain, and
     * app package name as intent extras when building the PendingIntent for
     * the auth wall. We read those extras here — no AssistStructure needed.
     *
     * Browser context: eTLD+1 domain match against vault entry URLs.
     * Native app context: package token substring match against vault entry URLs.
     * Multiple matches: first match wins (v2: picker UI).
     *
     * Returns null if extras are missing, no token can be extracted, or no
     * Login entries match — caller sets RESULT_CANCELED in that case.
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

        if (usernameIds.isEmpty() && passwordIds.isEmpty()) return null

        val webDomain = intent?.getStringExtra(EXTRA_WEB_DOMAIN)
        val appPackageName = intent?.getStringExtra(EXTRA_PACKAGE_NAME)

        val summariesJson = RustBridge.listLoginSummaries()
        val allCredentials = parseSummariesJson(summariesJson)

        val matches = if (webDomain != null) {
            val requestDomain = extractRegistrableDomain(webDomain) ?: return null
            allCredentials.filter { summary ->
                extractRegistrableDomain(summary.url) == requestDomain
            }
        } else {
            val token = appPackageName?.let { extractAppToken(it) } ?: return null
            allCredentials.filter { summary ->
                summary.url.contains(token, ignoreCase = true)
            }
        }

        if (matches.isEmpty()) return null

        val cred = matches.first()
        val presentation = RemoteViews(packageName, R.layout.autofill_unlock_item)
        val datasetBuilder = Dataset.Builder()
        usernameIds.forEach { id ->
            datasetBuilder.setValue(id, AutofillValue.forText(cred.username), presentation)
        }
        passwordIds.forEach { id ->
            datasetBuilder.setValue(id, AutofillValue.forText(cred.password), presentation)
        }

        val fillResponse = FillResponse.Builder()
            .addDataset(datasetBuilder.build())
            .build()

        return Intent().apply {
            putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, fillResponse)
        }
    }

    /**
     * Extracts a matchable token from an Android package name.
     * e.g. "com.paypal.android.p2pmobile" → "paypal"
     * Mirrors the logic in GabbroAutofillService exactly.
     */
    private fun extractAppToken(packageName: String): String? {
        val skipSegments = setOf("com", "org", "net", "app", "co", "io", "uk", "de", "fr", "ch")
        return packageName.split(".")
            .firstOrNull { it.length > 2 && it !in skipSegments }
    }

    /**
     * Extracts the eTLD+1 registrable domain from a URL or bare hostname.
     * Mirrors the logic in GabbroAutofillService exactly.
     */
    private fun extractRegistrableDomain(input: String?): String? {
        if (input.isNullOrBlank()) return null
        val withScheme = if (input.contains("://")) input else "https://$input"
        val host = android.net.Uri.parse(withScheme).host
            ?.lowercase()
            ?.trimEnd('.')
            ?: return null
        if (host.split(".").all { it.toIntOrNull() != null }) return null
        val labels = host.split(".")
        return if (labels.size >= 2) "${labels[labels.size - 2]}.${labels.last()}"
        else host
    }

    /**
     * Parses the JSON array returned by RustBridge.listLoginSummaries().
     * Mirrors the logic in GabbroAutofillService exactly.
     */
    private fun parseSummariesJson(json: String): List<CredentialSummary> {
        return try {
            val array = org.json.JSONArray(json)
            (0 until array.length()).map { i ->
                val obj = array.getJSONObject(i)
                val id = obj.getString("id")
                val entryJson = RustBridge.getEntry(id)
                val password = try {
                    org.json.JSONObject(entryJson).optString("password", "")
                } catch (_: Exception) { "" }
                CredentialSummary(
                    id = id,
                    username = obj.getString("username"),
                    url = obj.getString("url"),
                    password = password,
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /**
     * User pressed back or cancelled the unlock flow.
     * RESULT_CANCELED tells the OS to deliver nothing to the target field.
     */
    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        setResult(RESULT_CANCELED)
        finish()
    }
}