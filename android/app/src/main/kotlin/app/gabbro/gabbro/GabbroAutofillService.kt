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
import android.service.autofill.SaveInfo
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
 *       per match. No match → a SaveInfo-only response (no datasets), so no
 *       suggestion chip shows: the unlocked no-match path is silent by design.
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

        // Vault is unlocked — find Login entries that match the screen requesting
        // autofill, using the shared matcher (the same one UnlockActivity uses on the
        // locked-vault path). Matching runs on password-free summaries — no secret is
        // decrypted until a match is found.
        val summariesJson = RustBridge.listLoginSummaries()
        val matches = matchingCredentials(
            parseSummariesJson(summariesJson),
            parseResult.webDomain,
            parseResult.packageName,
            publicSuffixList,
        )

        // Native no-match: record the package (login fields were detected here) so the
        // Login editor can offer it as a tap-to-fill app-id suggestion.
        if (matches.isEmpty() && parseResult.webDomain == null &&
            shouldRecordPackage(parseResult.packageName, applicationContext.packageName)
        ) {
            RecentAutofillApps.record(applicationContext, parseResult.packageName!!.trim())
        }

        if (matches.isEmpty()) {
            // Unlocked but nothing matched: silent by design — no no-match indicator is
            // surfaced. No chip shows (the Android convention when nothing matches), the user
            // took no Gabbro action, and there is no Flutter engine on this path to localize a
            // message against the ARBs. We still offer to SAVE a brand-new login (a FillResponse
            // carrying only SaveInfo, no datasets).
            callback.onSuccess(buildSaveOnlyResponse(parseResult))
            return
        }

        // Fetch passwords only for matched entries — not for the whole vault.
        val matchesWithPasswords = matches.map { summary ->
            summary.copy(password = fetchPassword(summary.id))
        }

        callback.onSuccess(buildFillResponse(parseResult, matchesWithPasswords))
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess()
            return
        }

        val capture = CapturedSaveRequest.from(structure)
        val captured = capturedLoginFrom(capture.fields)

        // Web context wins over the host app's package: a login submitted in a
        // browser belongs to the site, never to the browser's own package id.
        val isWeb = capture.webDomain.isNotBlank()
        val url = if (isWeb) capture.webDomain else ""
        val appId = if (isWeb) "" else capture.packageName

        if (!shouldOfferSave(captured, url, appId)) {
            // No password, or no context to match on later — drop silently.
            callback.onSuccess()
            return
        }

        // The confirm + write happen in SaveActivity (after unlock); onSaveRequest
        // only captures and hands off. Callback is satisfied immediately.
        startActivity(buildSaveIntent(captured!!, url, appId))
        callback.onSuccess()
    }

    private fun buildSaveIntent(captured: CapturedLogin, url: String, appId: String): Intent =
        Intent(this, SaveActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(SaveActivity.EXTRA_USERNAME, captured.username)
            putExtra(SaveActivity.EXTRA_EMAIL, captured.email)
            putExtra(SaveActivity.EXTRA_PASSWORD, captured.password)
            putExtra(SaveActivity.EXTRA_URL, url)
            putExtra(SaveActivity.EXTRA_APP_ID, appId)
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
    internal fun buildAuthResponse(parsed: ParsedStructure): FillResponse {
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

        val responseBuilder = FillResponse.Builder()
            .addDataset(datasetBuilder.build())
        attachSaveInfo(responseBuilder, parsed)
        return responseBuilder.build()
    }

    // -------------------------------------------------------------------------
    // SaveInfo — the seam that makes the OS call onSaveRequest
    // -------------------------------------------------------------------------

    /**
     * Attach a SaveInfo so the OS offers to save after the user submits the form.
     * The password field is the required trigger; username/email are optional.
     * With no password field there is nothing worth saving as a Login (and
     * SaveInfo.Builder rejects an empty required-ids array), so none is attached.
     * Set on both the fill and the auth FillResponse, so a changed password saved
     * on the locked -> unlock -> fill path triggers a save too.
     */
    private fun attachSaveInfo(builder: FillResponse.Builder, parsed: ParsedStructure) {
        if (parsed.passwordIds.isEmpty()) return
        val saveInfo = SaveInfo.Builder(
            SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD,
            parsed.passwordIds.toTypedArray(),
        )
        val optional = (parsed.usernameIds + parsed.emailIds).toTypedArray()
        if (optional.isNotEmpty()) saveInfo.setOptionalIds(optional)
        builder.setSaveInfo(saveInfo.build())
    }

    /**
     * A FillResponse carrying only SaveInfo (no datasets) — returned when the vault is
     * unlocked but nothing matched, so the OS still offers to SAVE a brand-new login the
     * user types. Null when there is no password field (nothing worth saving), in which
     * case the caller passes null to onSuccess.
     */
    internal fun buildSaveOnlyResponse(parsed: ParsedStructure): FillResponse? {
        if (parsed.passwordIds.isEmpty()) return null
        val builder = FillResponse.Builder()
        attachSaveInfo(builder, parsed)
        return builder.build()
    }

    // -------------------------------------------------------------------------
    // Fill response — matched credentials
    // -------------------------------------------------------------------------

    internal fun buildFillResponse(
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
        attachSaveInfo(responseBuilder, parsed)
        return responseBuilder.build()
    }

    // -------------------------------------------------------------------------
    // Companion
    // -------------------------------------------------------------------------

    companion object {
        private const val REQUEST_CODE_UNLOCK = 1001
    }
}

// -----------------------------------------------------------------------------
// Shared autofill matching — the single source of truth for both the unlocked
// path (GabbroAutofillService) and the locked-vault path (UnlockActivity), so the
// two can never drift apart again. All pure top-level functions: `internal` so the
// same-module Robolectric unit tests exercise the real logic, and free of the
// service instance so UnlockActivity reuses them unchanged.
// -----------------------------------------------------------------------------

/**
 * Login entries that match the screen requesting autofill. Web context (webDomain
 * non-null): PSL eTLD+1 equality, so unrelated sites under a shared suffix never
 * collide (bbc.co.uk vs hsbc.co.uk — audit F-10). Native context: EXACT app_id
 * equality — never a loose/substring guess that could offer the wrong credential.
 *
 * [credentials] must be password-free summaries (see [parseSummariesJson]): matching
 * runs entirely on metadata, so no secret is decrypted until a match is found.
 */
internal fun matchingCredentials(
    credentials: List<CredentialSummary>,
    webDomain: String?,
    packageName: String?,
    psl: PublicSuffixList,
): List<CredentialSummary> {
    return if (webDomain != null) {
        val requestDomain = extractRegistrableDomain(webDomain, psl) ?: return emptyList()
        credentials.filter { summary ->
            extractRegistrableDomain(summary.url, psl) == requestDomain
        }
    } else {
        credentials.filter { summary ->
            nativeAppIdMatches(summary.appId, packageName)
        }
    }
}

/**
 * Registrable domain (eTLD+1) of a URL or bare host, using the Public Suffix List.
 * Returns null for blank/malformed input, a bare public suffix, or an IP address.
 * A single-label private host (e.g. "localhost") is kept as-is for intranet matching.
 */
internal fun extractRegistrableDomain(input: String?, psl: PublicSuffixList): String? {
    if (input.isNullOrBlank()) return null
    val withScheme = if (input.contains("://")) input else "https://$input"
    val host = android.net.Uri.parse(withScheme).host
        ?.lowercase()
        ?.trimEnd('.')
        ?: return null
    if (host.split(".").all { it.toIntOrNull() != null }) return null // reject IPs
    psl.registrableDomain(host)?.let { return it }
    // No registrable domain (host is a public suffix, or a single private label like
    // "localhost"). Keep a single-label private host as-is; drop a real public suffix.
    return host.takeIf { it.split(".").size == 1 && !psl.isListedSuffix(it) }
}

/** Parse the login-summary JSON feed into lightweight stubs — never a password. */
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

/** Decrypt the real password for a single matched credential. Called only after a match. */
internal fun fetchPassword(id: String): String {
    return try {
        val entryJson = RustBridge.getEntry(id)
        org.json.JSONObject(entryJson).optString("password", "")
    } catch (_: Exception) {
        ""
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
// capturedLoginFrom — typed values out of a SaveRequest (the save-path inverse of
// the fill path's ParsedStructure)
// -----------------------------------------------------------------------------

/**
 * A login captured from a SaveRequest: the typed username/email/password. Faithful
 * to the submitted form — username and email stay separate; the effective identifier
 * is resolved later, in the create-vs-update decision. The web/app context (url /
 * app_id) is recorded alongside by the caller.
 */
data class CapturedLogin(
    val username: String,
    val email: String,
    val password: String,
)

/**
 * Assemble a [CapturedLogin] from classified `(FieldKind, typed-value)` pairs pulled
 * from the SaveRequest's AssistStructure (classified by the same [classifyField] the
 * fill path uses). Password is mandatory — with none, or only blank, there is nothing
 * worth saving as a Login, so returns null. First non-blank value of each kind wins;
 * NONE fields are ignored.
 */
internal fun capturedLoginFrom(fields: List<Pair<FieldKind, String>>): CapturedLogin? {
    fun firstNonBlank(kind: FieldKind): String =
        fields.firstOrNull { it.first == kind && it.second.isNotBlank() }?.second.orEmpty()

    val password = firstNonBlank(FieldKind.PASSWORD)
    if (password.isBlank()) return null
    return CapturedLogin(
        username = firstNonBlank(FieldKind.USERNAME),
        email = firstNonBlank(FieldKind.EMAIL),
        password = password,
    )
}

// -----------------------------------------------------------------------------
// Layer C: which existing login a save would update, and create vs update vs no-op.
// Suggestion only — never a write. The user always confirms (and can override) in the
// Flutter save screen, so a save can never silently overwrite the wrong entry.
// -----------------------------------------------------------------------------

/** The suggested action for a captured login; the user can always override it. */
sealed class SaveDecision {
    /** No existing entry matched — offer to create a new login. */
    object Create : SaveDecision()

    /** An existing login matched and its password changed — offer to update it. */
    data class Update(val id: String) : SaveDecision()

    /** An existing login matched and the password is unchanged — nothing to save. */
    object NoOp : SaveDecision()
}

/**
 * The identifier used to tell two logins on the same site apart: the username, or the
 * email when there is no username. Trimmed and lowercased so casing/whitespace never
 * splits one account into two (emails are case-insensitive; usernames are in practice).
 */
internal fun effectiveIdentifier(username: String, email: String): String =
    username.ifBlank { email }.trim().lowercase()

/**
 * The existing login a save would update: the same-site/app entry (strict fill matcher
 * — PSL eTLD+1 / exact app_id) whose identifier equals the captured one. Returns null
 * when nothing matches, or when the captured login carries no identifier to disambiguate
 * by — a blank identifier never auto-targets an entry. Operates on password-free
 * summaries, so no secret is decrypted while resolving the target.
 */
internal fun matchSaveTarget(
    captured: CapturedLogin,
    summaries: List<CredentialSummary>,
    webDomain: String?,
    packageName: String?,
    psl: PublicSuffixList,
): CredentialSummary? {
    val wantId = effectiveIdentifier(captured.username, captured.email)
    if (wantId.isBlank()) return null
    return matchingCredentials(summaries, webDomain, packageName, psl)
        .firstOrNull { effectiveIdentifier(it.username, it.email) == wantId }
}

/**
 * The suggested [SaveDecision] from a resolved match: Create when nothing matched,
 * NoOp when the matched entry's current password already equals the captured one,
 * else Update. A suggestion only — the confirm screen can still override it.
 */
internal fun decideSave(
    matchedId: String?,
    matchedPassword: String?,
    capturedPassword: String,
): SaveDecision = when {
    matchedId == null -> SaveDecision.Create
    matchedPassword == capturedPassword -> SaveDecision.NoOp
    else -> SaveDecision.Update(matchedId)
}

/**
 * Whether `onSaveRequest` should offer to save: it needs a captured password
 * ([captured] non-null) AND a usable context to match the entry on later (a web
 * eTLD+1 or an app_id). Missing either, the save is dropped silently — the rare
 * no-context case (the OS almost always supplies a package or web domain) is not
 * worth a stored entry that could never be matched again.
 */
internal fun shouldOfferSave(captured: CapturedLogin?, url: String, appId: String): Boolean =
    captured != null && (url.isNotBlank() || appId.isNotBlank())

/** Picker display label for an existing login: username, else email, else url. */
internal fun candidateLabel(summary: CredentialSummary): String =
    summary.username.ifBlank { summary.email }.ifBlank { summary.url }

/**
 * The `/autofill_save` channel payload handed to the Dart confirm screen post-unlock:
 * the captured login + web/app context, the suggested [SaveDecision], and the same-site
 * `candidates` for the "choose another login" picker. The captured password crosses to
 * Dart because the write (and its `passwordHistoryExpiry`) happens there; matching and
 * the decision are computed in Kotlin (the single source of truth).
 */
internal fun saveContextJson(
    captured: CapturedLogin,
    url: String,
    appId: String,
    decision: SaveDecision,
    candidates: List<CredentialSummary>,
): String {
    val capturedObj = org.json.JSONObject()
        .put("username", captured.username)
        .put("email", captured.email)
        .put("password", captured.password)
        .put("url", url)
        .put("appId", appId)

    val decisionObj = org.json.JSONObject()
    when (decision) {
        is SaveDecision.Create -> decisionObj.put("action", "create")
        is SaveDecision.Update -> decisionObj.put("action", "update").put("matchedId", decision.id)
        is SaveDecision.NoOp -> decisionObj.put("action", "noop")
    }

    val candidatesArr = org.json.JSONArray()
    candidates.forEach { c ->
        candidatesArr.put(
            org.json.JSONObject().put("id", c.id).put("label", candidateLabel(c)),
        )
    }

    return org.json.JSONObject()
        .put("captured", capturedObj)
        .put("decision", decisionObj)
        .put("candidates", candidatesArr)
        .toString()
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
            // S-05: prefer the OS-attested requesting package over the window
            // title (which an app can shape) for native-app credential matching;
            // the title is only a fallback when the OS doesn't provide it.
            var packageName: String? = structure.activityComponent?.packageName
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

// -----------------------------------------------------------------------------
// CapturedSaveRequest — walks a SaveRequest AssistStructure collecting the typed
// field *values* (the save-path counterpart to ParsedStructure, which collects
// AutofillIds). Classification reuses the shared classifyField; only the value
// read (autofillValue) differs. The pure assembly lives in capturedLoginFrom.
// -----------------------------------------------------------------------------

data class CapturedSaveRequest(
    val fields: List<Pair<FieldKind, String>>,
    val webDomain: String,
    val packageName: String,
) {
    companion object {
        fun from(structure: AssistStructure): CapturedSaveRequest {
            val fields = mutableListOf<Pair<FieldKind, String>>()
            var webDomain: String? = null
            // S-05: prefer the OS-attested requesting package over the window
            // title for the saved entry's app_id; title is only a fallback.
            var packageName: String? = structure.activityComponent?.packageName
            for (i in 0 until structure.windowNodeCount) {
                val windowNode = structure.getWindowNodeAt(i)
                if (packageName == null) {
                    packageName = windowNode.title
                        ?.toString()
                        ?.substringBefore("/")
                        ?.trim()
                        ?.takeIf { it.contains(".") }
                }
                val domainOut = arrayOfNulls<String>(1)
                collect(windowNode.rootViewNode, fields, domainOut)
                if (webDomain == null) webDomain = domainOut[0]
            }
            return CapturedSaveRequest(fields, webDomain.orEmpty(), packageName.orEmpty())
        }

        private fun collect(
            node: AssistStructure.ViewNode,
            fields: MutableList<Pair<FieldKind, String>>,
            webDomainOut: Array<String?>,
        ) {
            if (webDomainOut[0] == null) {
                webDomainOut[0] = node.webDomain?.takeIf { it.isNotBlank() }
            }

            if (node.autofillId != null) {
                val htmlAttrs = node.htmlInfo?.attributes
                fun htmlAttr(name: String): String? =
                    htmlAttrs?.firstOrNull { it.first.equals(name, ignoreCase = true) }?.second

                val kind = classifyField(
                    autofillHints = node.autofillHints?.toList(),
                    inputType = node.inputType,
                    htmlType = htmlAttr("type"),
                    htmlAutocomplete = htmlAttr("autocomplete"),
                    hint = node.hint,
                    idEntry = node.idEntry,
                    htmlName = htmlAttr("name"),
                    htmlId = htmlAttr("id"),
                )
                if (kind != FieldKind.NONE) {
                    val value = node.autofillValue
                        ?.let { if (it.isText) it.textValue.toString() else null }
                        .orEmpty()
                    fields.add(kind to value)
                }
            }

            for (i in 0 until node.childCount) {
                collect(node.getChildAt(i), fields, webDomainOut)
            }
        }
    }
}
