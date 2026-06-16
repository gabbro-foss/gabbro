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

    // Loaded once from the vendored asset on first match. Backs eTLD+1 matching.
    private val publicSuffixList: PublicSuffixList by lazy { PublicSuffixList.fromAsset(this) }

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

        // Debug builds only: dump the raw structure to logcat so a failing page
        // (esp. a Chromium SPA exposing no fields) can be diagnosed. Compiled out
        // of release. Metadata only — never field values.
        if (BuildConfig.DEBUG) {
            ParsedStructure.dumpStructure(structure)
            android.util.Log.d(
                "GabbroAutofill",
                "parse result: usernames=${parseResult.usernameIds.size} " +
                    "passwords=${parseResult.passwordIds.size} " +
                    "web=${parseResult.webDomain} pkg=${parseResult.packageName}",
            )
        }

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
            // Native app context — match the requesting package against entries
            // that explicitly recorded it (exact equality; no loose matching).
            val requestPackage = parseResult.packageName
            val nativeMatches = parseSummariesJson(summariesJson).filter { summary ->
                nativeAppIdMatches(summary.appId, requestPackage)
            }
            // No match: record the package (login fields were detected here) so the
            // Login editor can offer it as a tap-to-fill app-id suggestion.
            if (nativeMatches.isEmpty() &&
                shouldRecordPackage(requestPackage, applicationContext.packageName)
            ) {
                RecentAutofillApps.record(applicationContext, requestPackage!!.trim())
            }
            nativeMatches
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
            putParcelableArrayListExtra(
                UnlockActivity.EXTRA_EMAIL_IDS,
                ArrayList(parsed.emailIds),
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

        (parsed.usernameIds + parsed.emailIds + parsed.passwordIds).forEach { id ->
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
                val v = fillValueFor(FieldKind.USERNAME, cred.username, cred.email)
                datasetBuilder.setValue(id, AutofillValue.forText(v), presentation)
            }
            parsed.emailIds.forEach { id ->
                val v = fillValueFor(FieldKind.EMAIL, cred.username, cred.email)
                datasetBuilder.setValue(id, AutofillValue.forText(v), presentation)
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

    // `internal` (not `private`) so same-module JVM unit tests can exercise the
    // real domain-matching logic under Robolectric. No runtime behaviour change.
    internal fun extractRegistrableDomain(input: String?): String? {
        if (input.isNullOrBlank()) return null
        val withScheme = if (input.contains("://")) input else "https://$input"
        val host = android.net.Uri.parse(withScheme).host
            ?.lowercase()
            ?.trimEnd('.')
            ?: return null
        if (host.split(".").all { it.toIntOrNull() != null }) return null // reject IPs
        publicSuffixList.registrableDomain(host)?.let { return it }
        // No registrable domain (host is a public suffix, or a single private label
        // like "localhost"). Keep a single-label private host as-is for intranet
        // matching; drop anything that is itself a real public suffix.
        return host.takeIf { it.split(".").size == 1 && !publicSuffixList.isListedSuffix(it) }
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
                    appId = obj.optString("app_id", ""),
                    email = obj.optString("email", ""),
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
    /// Recorded Android package name for native-app matching; "" when unset.
    val appId: String = "",
    /// Email/identifier routed to email-typed fields; "" when unset.
    val email: String = "",
)

/**
 * The value to fill into a field of the given [kind], from an entry's [username]
 * and [email]. Each falls back to the other when blank, so single-identifier
 * entries (and fields that accept either) still fill correctly.
 */
internal fun fillValueFor(kind: FieldKind, username: String, email: String): String =
    when (kind) {
        FieldKind.EMAIL -> email.ifBlank { username }
        FieldKind.USERNAME -> username.ifBlank { email }
        else -> ""
    }

// -----------------------------------------------------------------------------
// Native-app matching + capture — pure helpers (unit-tested without the framework)
// -----------------------------------------------------------------------------

/**
 * Whether a vault entry's recorded app id matches the app requesting autofill.
 * EXACT package-name equality only. An unset (blank) app id matches nothing —
 * the cardinal rule for a password manager: never a loose/substring guess that
 * could offer the wrong credential.
 */
internal fun nativeAppIdMatches(appId: String?, packageName: String?): Boolean {
    val a = appId?.trim().orEmpty()
    val p = packageName?.trim().orEmpty()
    return a.isNotEmpty() && a == p
}

/**
 * Whether a native package should be recorded for the "recently seen apps"
 * suggestion list: a non-blank third-party package, never our own app.
 */
internal fun shouldRecordPackage(packageName: String?, ownPackage: String): Boolean {
    val p = packageName?.trim().orEmpty()
    return p.isNotEmpty() && p != ownPackage
}

/**
 * Pure list update for the recent-apps store: put `pkg` first, drop any prior
 * occurrence (most-recent-first, no duplicates), and cap the size (oldest fall
 * off the end).
 */
internal fun recentAppsUpdated(existing: List<String>, pkg: String, cap: Int): List<String> {
    return (listOf(pkg) + existing.filter { it != pkg }).take(cap)
}

/**
 * App-private store of native apps that requested autofill but matched no entry,
 * surfaced by the Login editor as tap-to-fill suggestions for the app-id field
 * (so users need not hunt for a package name). Metadata only — package names,
 * no secrets — capped and clearable.
 */
object RecentAutofillApps {
    private const val PREFS = "gabbro_recent_autofill_apps"
    private const val KEY = "packages"
    const val CAP = 10

    fun record(context: android.content.Context, packageName: String) {
        val prefs = context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE)
        val updated = recentAppsUpdated(read(prefs), packageName, CAP)
        prefs.edit().putString(KEY, updated.joinToString("\n")).apply()
    }

    fun recent(context: android.content.Context): List<String> =
        read(context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE))

    private fun read(prefs: android.content.SharedPreferences): List<String> =
        prefs.getString(KEY, "").orEmpty().split("\n").filter { it.isNotBlank() }
}

// -----------------------------------------------------------------------------
// classifyField — pure per-field decision
// -----------------------------------------------------------------------------

/** How a single field should be filled. */
enum class FieldKind { USERNAME, EMAIL, PASSWORD, NONE }

/**
 * Decide whether one field is a username, password, or neither, from the signals
 * carried on its ViewNode. Pulled out of the AssistStructure walk so it can be
 * unit-tested without the framework (the `android.*` constants below are
 * compile-time-inlined). `collectIds` extracts the signals — including the HTML
 * attributes Chromium browsers carry in `htmlInfo` — and calls this.
 *
 * Signals are weighed most- to least-reliable: explicit autofill hints, then
 * HTML attributes (the web-page truth that SPAs otherwise leave blank on the
 * Android side), then the `inputType` bitmask, then a keyword fallback over the
 * field's metadata. The first tier to match wins — so e.g. an HTML
 * `type=password` outranks a stray "username" in the field id.
 */
internal fun classifyField(
    autofillHints: List<String>?,
    inputType: Int,
    htmlType: String?,
    htmlAutocomplete: String?,
    hint: String?,
    idEntry: String?,
    htmlName: String?,
    htmlId: String?,
): FieldKind {
    // Tier 1: explicit autofill hints. Email signals route to EMAIL, username
    // signals to USERNAME (so the fill can put the email in email fields).
    autofillHints?.let { hints ->
        if (hints.any {
                it.equals(android.view.View.AUTOFILL_HINT_EMAIL_ADDRESS, ignoreCase = true) ||
                    it.equals("email", ignoreCase = true)
            }
        ) {
            return FieldKind.EMAIL
        }
        if (hints.any {
                it.equals(android.view.View.AUTOFILL_HINT_USERNAME, ignoreCase = true) ||
                    it.equals("username", ignoreCase = true)
            }
        ) {
            return FieldKind.USERNAME
        }
        if (hints.any {
                it.equals(android.view.View.AUTOFILL_HINT_PASSWORD, ignoreCase = true) ||
                    it.equals("current-password", ignoreCase = true) ||
                    it.equals("new-password", ignoreCase = true)
            }
        ) {
            return FieldKind.PASSWORD
        }
    }

    // Tier 2: HTML attributes — the signal web-apps/SPAs carry in htmlInfo but
    // leave off the Android autofill hints / inputType.
    val htmlT = htmlType?.lowercase()
    val autocomplete = htmlAutocomplete?.lowercase()
    if (htmlT == "password" ||
        autocomplete == "current-password" ||
        autocomplete == "new-password" ||
        autocomplete == "password"
    ) {
        return FieldKind.PASSWORD
    }
    if (htmlT == "email" || autocomplete == "email") return FieldKind.EMAIL
    if (autocomplete == "username") return FieldKind.USERNAME

    // Tier 3: inputType bitmask — most native apps that declare no hints.
    if (inputType and android.text.InputType.TYPE_MASK_CLASS ==
        android.text.InputType.TYPE_CLASS_TEXT
    ) {
        when (inputType and android.text.InputType.TYPE_MASK_VARIATION) {
            android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD,
            android.text.InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            android.text.InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
            -> return FieldKind.PASSWORD

            android.text.InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
            android.text.InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
            -> return FieldKind.EMAIL
        }
    }

    // Tier 4: keyword fallback. The html name/id attributes are only trusted on a
    // real form control (htmlType present) — a <form name="login"> container also
    // carries an html name but no type, and must not be matched as a field.
    // idEntry/hint stay unconditional (native apps have no htmlInfo).
    val htmlFieldKeywords = if (htmlType != null) listOfNotNull(htmlName, htmlId) else emptyList()

    // Password only from the more reliable name/id (a free-text "hint" of
    // "password" is too noisy); email/username also from hint.
    val passwordSources = (listOfNotNull(idEntry) + htmlFieldKeywords).map { it.lowercase() }
    if (passwordSources.any { it.contains("password") }) return FieldKind.PASSWORD
    val userSources = (listOfNotNull(hint, idEntry) + htmlFieldKeywords).map { it.lowercase() }
    if (userSources.any { it.contains("email") }) return FieldKind.EMAIL
    if (userSources.any {
            it.contains("username") || it.contains("login") || it.contains("phone")
        }
    ) {
        return FieldKind.USERNAME
    }

    return FieldKind.NONE
}

// -----------------------------------------------------------------------------
// formatNodeDiagnostic — pure log-line formatter for the debug structure dump
// -----------------------------------------------------------------------------

/**
 * Render one ViewNode's signals into a single stable diagnostic line. Used only
 * by the debug-gated [dumpStructure] so a logcat capture on a failing page (esp.
 * a Chromium SPA that hands the framework no field structure) shows exactly what,
 * if anything, the browser exposed.
 *
 * Pure so it can be unit-tested without the framework. Logs structural metadata
 * only — never an AutofillValue / typed text.
 */
internal fun formatNodeDiagnostic(
    className: String?,
    hasAutofillId: Boolean,
    autofillHints: List<String>?,
    inputType: Int,
    htmlType: String?,
    htmlName: String?,
    htmlAutocomplete: String?,
    htmlId: String?,
    webDomain: String?,
    idEntry: String?,
    hint: String?,
    childCount: Int,
): String {
    val htmlAttrs = listOf(
        "type" to htmlType,
        "name" to htmlName,
        "autocomplete" to htmlAutocomplete,
        "id" to htmlId,
    ).filter { !it.second.isNullOrBlank() }
        .joinToString(",") { "${it.first}=${it.second}" }

    val hints = autofillHints?.filter { it.isNotBlank() }?.joinToString(",").orEmpty()

    return buildString {
        append(className ?: "?")
        append(" afId=").append(if (hasAutofillId) "yes" else "no")
        append(" inputType=0x").append(Integer.toHexString(inputType))
        append(" html[").append(htmlAttrs).append("]")
        append(" hints[").append(hints).append("]")
        if (!idEntry.isNullOrBlank()) append(" idEntry=").append(idEntry)
        if (!hint.isNullOrBlank()) append(" hint=").append(hint)
        if (!webDomain.isNullOrBlank()) append(" web=").append(webDomain)
        append(" children=").append(childCount)
    }
}

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
    val emailIds: List<AutofillId> = emptyList(),
) {
    fun isEmpty(): Boolean =
        usernameIds.isEmpty() && emailIds.isEmpty() && passwordIds.isEmpty()

    companion object {
        fun from(structure: AssistStructure): ParsedStructure {
            val usernameIds = mutableListOf<AutofillId>()
            val emailIds = mutableListOf<AutofillId>()
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
                collectIds(root, usernameIds, emailIds, passwordIds, foundDomain)
                if (webDomain == null) webDomain = foundDomain[0]
            }

            return ParsedStructure(
                usernameIds = usernameIds,
                passwordIds = passwordIds,
                webDomain = webDomain,
                packageName = packageName,
                emailIds = emailIds,
            )
        }

        /**
         * Debug-only: walk every node and emit its raw signals to logcat
         * (`adb logcat -s GabbroAutofill`). Gated by the caller behind
         * BuildConfig.DEBUG so it is compiled out of release builds. Diagnoses
         * pages where `from()` finds no fields — shows whether the browser
         * exposed any structure at all. Metadata only, never field values.
         */
        fun dumpStructure(structure: AssistStructure) {
            android.util.Log.d(LOG_TAG, "=== AssistStructure dump: windows=${structure.windowNodeCount} ===")
            for (i in 0 until structure.windowNodeCount) {
                val windowNode = structure.getWindowNodeAt(i)
                android.util.Log.d(LOG_TAG, "window[$i] title=${windowNode.title}")
                dumpNode(windowNode.rootViewNode, 0)
            }
        }

        private fun dumpNode(node: AssistStructure.ViewNode, depth: Int) {
            val htmlAttrs = node.htmlInfo?.attributes
            fun htmlAttr(name: String): String? =
                htmlAttrs?.firstOrNull { it.first.equals(name, ignoreCase = true) }?.second

            val line = formatNodeDiagnostic(
                className = node.className,
                hasAutofillId = node.autofillId != null,
                autofillHints = node.autofillHints?.toList(),
                inputType = node.inputType,
                htmlType = htmlAttr("type"),
                htmlName = htmlAttr("name"),
                htmlAutocomplete = htmlAttr("autocomplete"),
                htmlId = htmlAttr("id"),
                webDomain = node.webDomain,
                idEntry = node.idEntry,
                hint = node.hint,
                childCount = node.childCount,
            )
            android.util.Log.d(LOG_TAG, "  ".repeat(depth) + line)

            for (i in 0 until node.childCount) {
                dumpNode(node.getChildAt(i), depth + 1)
            }
        }

        private const val LOG_TAG = "GabbroAutofill"

        private fun collectIds(
            node: AssistStructure.ViewNode,
            usernameIds: MutableList<AutofillId>,
            emailIds: MutableList<AutofillId>,
            passwordIds: MutableList<AutofillId>,
            webDomainOut: Array<String?>,
        ) {
            // Collect webDomain from any node in the tree.
            if (webDomainOut[0] == null) {
                webDomainOut[0] = node.webDomain?.takeIf { it.isNotBlank() }
            }

            val id = node.autofillId

            if (id != null) {
                // Chromium browsers carry the real field truth in htmlInfo HTML
                // attributes (type=password, autocomplete=...) that web-apps/SPAs
                // often leave off the Android hints/inputType — extract them as a
                // signal for classifyField.
                val htmlAttrs = node.htmlInfo?.attributes
                fun htmlAttr(name: String): String? =
                    htmlAttrs?.firstOrNull { it.first.equals(name, ignoreCase = true) }?.second

                when (
                    classifyField(
                        autofillHints = node.autofillHints?.toList(),
                        inputType = node.inputType,
                        htmlType = htmlAttr("type"),
                        htmlAutocomplete = htmlAttr("autocomplete"),
                        hint = node.hint,
                        idEntry = node.idEntry,
                        htmlName = htmlAttr("name"),
                        htmlId = htmlAttr("id"),
                    )
                ) {
                    FieldKind.USERNAME -> usernameIds.add(id)
                    FieldKind.EMAIL -> emailIds.add(id)
                    FieldKind.PASSWORD -> passwordIds.add(id)
                    FieldKind.NONE -> {}
                }
            }

            for (i in 0 until node.childCount) {
                collectIds(node.getChildAt(i), usernameIds, emailIds, passwordIds, webDomainOut)
            }
        }
    }
}
