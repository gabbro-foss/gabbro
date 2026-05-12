package app.gabbro.gabbro

import android.app.assist.AssistStructure
import android.content.Intent
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
    }

    override fun getDartEntrypointFunctionName(): String = "autofillUnlockMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "unlock" -> {
                        // Vault unlock is handled by the Flutter layer via the
                        // normal Rust bridge. Once unlocked, build a real
                        // FillResponse and deliver it to the target field.
                        val fillIntent = buildFillIntent()
                        if (fillIntent != null) {
                            setResult(RESULT_OK, fillIntent)
                        } else {
                            // No matching credentials found — cancel gracefully.
                            setResult(RESULT_CANCELED)
                        }
                        finish()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Re-runs domain matching after unlock and builds a FillResponse.
     *
     * The OS puts the AssistStructure into the launching intent automatically
     * under EXTRA_ASSIST_STRUCTURE. We extract it, re-parse the structure,
     * match Login entries by domain, and build a Dataset for the first match.
     * Multiple matches: first match wins for now (v2: picker UI).
     *
     * Returns null if the structure is missing, no domain is found, or no
     * Login entries match — caller sets RESULT_CANCELED in that case.
     */
    private fun buildFillIntent(): Intent? {
        val structure: AssistStructure = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra(AutofillManager.EXTRA_ASSIST_STRUCTURE, AssistStructure::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(AutofillManager.EXTRA_ASSIST_STRUCTURE)
        } ?: return null

        val parsed = ParsedStructure.from(structure)
        if (parsed.isEmpty()) return null

        val requestDomain = extractRegistrableDomain(parsed.webDomain) ?: return null

        val summariesJson = RustBridge.listLoginSummaries()
        val matches = parseSummariesJson(summariesJson).filter { summary ->
            extractRegistrableDomain(summary.url) == requestDomain
        }
        if (matches.isEmpty()) return null

        val cred = matches.first()
        val presentation = RemoteViews(packageName, R.layout.autofill_unlock_item)
        val datasetBuilder = Dataset.Builder()
        parsed.usernameIds.forEach { id ->
            datasetBuilder.setValue(id, AutofillValue.forText(cred.username), presentation)
        }
        parsed.passwordIds.forEach { id ->
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