package app.gabbro.gabbro

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillContext
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews

/**
 * GabbroAutofillService — fill-only path (save requests deferred to a later session).
 *
 * Lifecycle (fill path):
 *   1. Android calls onFillRequest() when the user focuses a login field.
 *   2. We walk the AssistStructure to find username/password AutofillIds.
 *   3a. Vault locked  → return an authentication Dataset whose IntentSender
 *       launches UnlockActivity. The OS presents it as a single suggestion;
 *       tapping it opens UnlockActivity, which unlocks the vault and returns
 *       the credential directly to the target field.
 *   3b. Vault unlocked → domain-match Login entries and return one Dataset
 *       per match. Returns null if no matches found.
 */
class GabbroAutofillService : AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        // The most recent FillContext contains the screen the user is on.
        val structure: AssistStructure = request.fillContexts
            .lastOrNull()
            ?.structure
            ?: run {
                callback.onSuccess(null)
                return
            }

        // Walk the view tree to collect all username/password AutofillIds.
        val parseResult = ParsedStructure.from(structure)
        if (parseResult.isEmpty()) {
            // No autofillable fields found on this screen — nothing to offer.
            callback.onSuccess(null)
            return
        }

        // Check whether the Rust vault session is currently unlocked.
        val unlocked = RustBridge.isVaultUnlocked()

        if (!unlocked) {
            callback.onSuccess(buildAuthResponse(parseResult))
            return
        }

        // Vault is unlocked — find Login entries whose domain matches the
        // domain of the screen requesting autofill.
        val summariesJson = RustBridge.listLoginSummaries()
        val matches = if (parseResult.webDomain != null) {
            // Browser context — exact eTLD+1 domain match.
            val requestDomain = extractRegistrableDomain(parseResult.webDomain)
            if (requestDomain == null) {
                callback.onSuccess(null)
                return
            }
            parseSummariesJson(summariesJson).filter { summary ->
                extractRegistrableDomain(summary.url) == requestDomain
            }
        } else {
            // Native app context — extract app name from package and check
            // if any vault entry URL contains it as a substring.
            val packageName = parseResult.packageName ?: ""
            val appToken = extractAppToken(packageName)
            if (appToken == null) {
                callback.onSuccess(null)
                return
            }
            parseSummariesJson(summariesJson).filter { summary ->
                summary.url.contains(appToken, ignoreCase = true)
            }
        }

        if (matches.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        // Fetch passwords only for matched entries — not for the whole vault.
        val matchesWithPasswords = matches.map { summary ->
            summary.copy(password = fetchPassword(summary.id))
        }

        callback.onSuccess(buildFillResponse(parseResult, matchesWithPasswords))
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // Save requests deferred to a dedicated session.
        callback.onSuccess()
    }

    // -------------------------------------------------------------------------
    // Authentication wall
    // -------------------------------------------------------------------------

    /**
     * Builds a FillResponse containing a single Dataset whose value is an
     * IntentSender pointing at UnlockActivity.  The OS renders it as a chip
     * in the autofill dropdown; tapping it launches UnlockActivity.
     *
     * The Dataset must have an AutofillValue set on each field — we pass a
     * placeholder empty string.  The real values are delivered by
     * UnlockActivity after the vault is unlocked.
     */
    private fun buildAuthResponse(parsed: ParsedStructure): FillResponse {
        val presentation = RemoteViews(packageName, R.layout.autofill_unlock_item)

        val unlockIntent = Intent(this, UnlockActivity::class.java).apply {
            putParcelableArrayListExtra(
                UnlockActivity.EXTRA_USERNAME_IDS,
                ArrayList(parsed.usernameIds),
            )
            putParcelableArrayListExtra(
                UnlockActivity.EXTRA_PASSWORD_IDS,
                ArrayList(parsed.passwordIds),
            )
            putExtra(UnlockActivity.EXTRA_WEB_DOMAIN, parsed.webDomain)
            putExtra(UnlockActivity.EXTRA_PACKAGE_NAME, parsed.packageName)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            REQUEST_CODE_UNLOCK,
            unlockIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val datasetBuilder = Dataset.Builder()

        parsed.usernameIds.forEach { id ->
            datasetBuilder.setValue(id, AutofillValue.forText(""), presentation)
        }
        parsed.passwordIds.forEach { id ->
            datasetBuilder.setValue(id, AutofillValue.forText(""), presentation)
        }

        datasetBuilder.setAuthentication(pendingIntent.intentSender)

        return FillResponse.Builder()
            .addDataset(datasetBuilder.build())
            .build()
    }

    // -------------------------------------------------------------------------
    // Fill response — matched credentials
    // -------------------------------------------------------------------------

    private fun buildFillResponse(
        parsed: ParsedStructure,
        matches: List<CredentialSummary>,
    ): FillResponse {
        val responseBuilder = FillResponse.Builder()
        matches.forEach { cred ->
            val presentation = RemoteViews(packageName, R.layout.autofill_unlock_item)
            val datasetBuilder = Dataset.Builder()
            parsed.usernameIds.forEach { id ->
                datasetBuilder.setValue(id, AutofillValue.forText(cred.username), presentation)
            }
            parsed.passwordIds.forEach { id ->
                datasetBuilder.setValue(id, AutofillValue.forText(cred.password), presentation)
            }
            responseBuilder.addDataset(datasetBuilder.build())
        }
        return responseBuilder.build()
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /**
     * Extracts a matchable token from an Android package name.
     * e.g. "com.paypal.android.p2pmobile" → "paypal"
     * Drops known TLD-like prefixes (com, org, net, app, co, io)
     * and takes the first remaining segment.
     * Returns null if no usable token can be extracted.
     */
    private fun extractAppToken(packageName: String): String? {
        val skipSegments = setOf("com", "org", "net", "app", "co", "io", "uk", "de", "fr", "ch")
        return packageName.split(".")
            .firstOrNull { it.length > 2 && it !in skipSegments }
    }

    // `internal` (not `private`) so same-module JVM unit tests can exercise the
    // real domain-matching logic under Robolectric. No runtime behaviour change.
    internal fun extractRegistrableDomain(input: String?): String? {
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

    /** Parse summaries JSON into lightweight stubs — no password fetch. */
    // `internal` (not `private`) for the same unit-test reason as
    // extractRegistrableDomain above. No runtime behaviour change.
    internal fun parseSummariesJson(json: String): List<CredentialSummary> {
        return try {
            val array = org.json.JSONArray(json)
            (0 until array.length()).map { i ->
                val obj = array.getJSONObject(i)
                CredentialSummary(
                    id = obj.getString("id"),
                    username = obj.getString("username"),
                    url = obj.getString("url"),
                    password = "",
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** Fetch the real password for a single matched credential. */
    private fun fetchPassword(id: String): String {
        return try {
            val entryJson = RustBridge.getEntry(id)
            org.json.JSONObject(entryJson).optString("password", "")
        } catch (_: Exception) {
            ""
        }
    }

    // -------------------------------------------------------------------------
    // Companion
    // -------------------------------------------------------------------------

    companion object {
        private const val REQUEST_CODE_UNLOCK = 1001
    }
}

// -----------------------------------------------------------------------------
// CredentialSummary — parsed login entry for fill path
// -----------------------------------------------------------------------------

data class CredentialSummary(
    val id: String,
    val username: String,
    val url: String,
    val password: String,
)

// -----------------------------------------------------------------------------
// ParsedStructure — walks AssistStructure, collects AutofillIds by hint type
// -----------------------------------------------------------------------------

/**
 * Holds the AutofillIds found in a single AssistStructure traversal.
 * Separated from the service class so it can be unit-tested independently.
 */
data class ParsedStructure(
    val usernameIds: List<AutofillId>,
    val passwordIds: List<AutofillId>,
    val webDomain: String?,
    val packageName: String?,
) {
    fun isEmpty(): Boolean = usernameIds.isEmpty() && passwordIds.isEmpty()

    companion object {
        fun from(structure: AssistStructure): ParsedStructure {
            val usernameIds = mutableListOf<AutofillId>()
            val passwordIds = mutableListOf<AutofillId>()
            var webDomain: String? = null
            var packageName: String? = null
            for (i in 0 until structure.windowNodeCount) {
                val windowNode = structure.getWindowNodeAt(i)
                val root = windowNode.rootViewNode
                if (packageName == null) {
                    packageName = windowNode.title
                        ?.toString()
                        ?.substringBefore("/")
                        ?.trim()
                        ?.takeIf { it.contains(".") }
                }
                val foundDomain = arrayOfNulls<String>(1)
                collectIds(root, usernameIds, passwordIds, foundDomain)
                if (webDomain == null) webDomain = foundDomain[0]
            }

            return ParsedStructure(usernameIds, passwordIds, webDomain, packageName)
        }

        private fun collectIds(
            node: AssistStructure.ViewNode,
            usernameIds: MutableList<AutofillId>,
            passwordIds: MutableList<AutofillId>,
            webDomainOut: Array<String?>,
        ) {
            // Collect webDomain from any node in the tree.
            if (webDomainOut[0] == null) {
                webDomainOut[0] = node.webDomain?.takeIf { it.isNotBlank() }
            }

            val hints = node.autofillHints
            val id = node.autofillId

            if (id != null) {
                when {
                    // Explicit autofill hints — most reliable signal.
                    // Covers both Android constants and HTML autocomplete attribute values
                    // (e.g. "email", "username") used by Chromium-based browsers.
                    hints != null && hints.any {
                        it.equals(android.view.View.AUTOFILL_HINT_USERNAME, ignoreCase = true) ||
                        it.equals(android.view.View.AUTOFILL_HINT_EMAIL_ADDRESS, ignoreCase = true) ||
                        it.equals("email", ignoreCase = true) ||
                        it.equals("username", ignoreCase = true)
                    } -> usernameIds.add(id)

                    hints != null && hints.any {
                        it.equals(android.view.View.AUTOFILL_HINT_PASSWORD, ignoreCase = true) ||
                        it.equals("current-password", ignoreCase = true) ||
                        it.equals("new-password", ignoreCase = true)
                    } -> passwordIds.add(id)

                    // Fallback: inputType bitmask — used by most native apps
                    // that don't declare explicit autofill hints.
                    else -> {
                        val inputType = node.inputType
                        val typeClass = inputType and android.text.InputType.TYPE_MASK_CLASS
                        val typeVariation = inputType and android.text.InputType.TYPE_MASK_VARIATION

                        if (typeClass == android.text.InputType.TYPE_CLASS_TEXT) {
                            when (typeVariation) {
                                android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD,
                                android.text.InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                                android.text.InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ->
                                    passwordIds.add(id)

                                android.text.InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                                android.text.InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS ->
                                    usernameIds.add(id)

                                else -> {
                                    // Last resort: check the field's hint text for
                                    // username/email keywords. Catches fields like
                                    // PayPal's email_or_phone_input (inputType=1,
                                    // variation=0, hint="Email").
                                    val hint = node.hint?.lowercase() ?: ""
                                    val entryId = node.idEntry?.lowercase() ?: ""
                                    if (hint.contains("email") || hint.contains("username") ||
                                        hint.contains("login") || hint.contains("phone") ||
                                        entryId.contains("email") || entryId.contains("username") ||
                                        entryId.contains("login") || entryId.contains("phone")) {
                                        usernameIds.add(id)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            for (i in 0 until node.childCount) {
                collectIds(node.getChildAt(i), usernameIds, passwordIds, webDomainOut)
            }
        }
    }
}
