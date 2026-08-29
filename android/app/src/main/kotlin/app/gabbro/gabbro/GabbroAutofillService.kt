package app.gabbro.gabbro

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.Field
import android.service.autofill.FillCallback
import android.service.autofill.FillContext
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.Presentations
import android.service.autofill.SaveCallback
import android.service.autofill.SaveInfo
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews

/**
 * Locked vault: a single authentication Dataset whose IntentSender opens
 * UnlockActivity, which fills the target field itself after unlock.
 * Unlocked with no match: a SaveInfo-only response, so no chip shows (the
 * Android convention) while the OS still offers to save a new login.
 */
class GabbroAutofillService : AutofillService() {

    private val publicSuffixList: PublicSuffixList by lazy { PublicSuffixList.fromAsset(this) }

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val structure: AssistStructure = request.fillContexts
            .lastOrNull()
            ?.structure
            ?: run {
                callback.onSuccess(null)
                return
            }

        val parseResult = ParsedStructure.from(structure)

        // Metadata only, never field values. Compiled out of release.
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
            callback.onSuccess(null)
            return
        }

        val unlocked = RustBridge.isVaultUnlocked()

        if (!unlocked) {
            callback.onSuccess(buildAuthResponse(parseResult))
            return
        }

        // Password-free summaries: no secret is decrypted until a match is found.
        val summariesJson = RustBridge.listLoginSummaries()
        val matches = matchingCredentials(
            parseSummariesJson(summariesJson),
            parseResult.webDomain,
            parseResult.packageName,
            publicSuffixList,
        )

        if (matches.isEmpty()) {
            // Silent: no chip is the Android convention, and there is no Flutter
            // engine on this path to localize a message.
            callback.onSuccess(buildSaveOnlyResponse(parseResult))
            return
        }

        // Passwords for the matches only, never the whole vault.
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

        // A login submitted in a browser belongs to the site, never to the
        // browser's own package id.
        val isWeb = capture.webDomain.isNotBlank()
        val url = if (isWeb) capture.webDomain else ""
        val appId = if (isWeb) "" else capture.packageName

        if (!shouldOfferSave(captured, url, appId)) {
            callback.onSuccess()
            return
        }

        // Confirm and write happen in SaveActivity after unlock; the callback
        // must not wait for them.
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

    /**
     * The Dataset needs a value on every field, so each gets an empty
     * placeholder; UnlockActivity delivers the real values after unlock.
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
            datasetBuilder.fillField(id, AutofillValue.forText(""), presentation)
        }

        datasetBuilder.setAuthentication(pendingIntent.intentSender)

        val responseBuilder = FillResponse.Builder()
            .addDataset(datasetBuilder.build())
        attachSaveInfo(responseBuilder, parsed)
        return responseBuilder.build()
    }

    /**
     * SaveInfo is what makes the OS call onSaveRequest. Without a password
     * field there is nothing worth saving (and SaveInfo.Builder rejects an
     * empty required-ids array). Attached to the auth response too, so a
     * password changed on the locked -> unlock -> fill path still saves.
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

    /** Null without a password field: nothing worth saving. */
    internal fun buildSaveOnlyResponse(parsed: ParsedStructure): FillResponse? {
        if (parsed.passwordIds.isEmpty()) return null
        val builder = FillResponse.Builder()
        attachSaveInfo(builder, parsed)
        return builder.build()
    }

    internal fun buildFillResponse(
        parsed: ParsedStructure,
        matches: List<CredentialSummary>,
    ): FillResponse {
        val responseBuilder = FillResponse.Builder()
        matches.forEach { cred ->
            val presentation = RemoteViews(packageName, R.layout.autofill_unlock_item)
            responseBuilder.addDataset(
                buildFillDataset(
                    parsed.usernameIds,
                    parsed.emailIds,
                    parsed.passwordIds,
                    cred,
                    presentation,
                ),
            )
        }
        attachSaveInfo(responseBuilder, parsed)
        return responseBuilder.build()
    }

    companion object {
        private const val REQUEST_CODE_UNLOCK = 1001
    }
}

// The matching helpers below are shared by the unlocked path (this service) and
// the locked path (UnlockActivity) so the two cannot drift. Top-level and
// `internal` so the same-module unit tests run the real logic.

/**
 * Web: PSL eTLD+1 equality, so unrelated sites under a shared suffix never
 * collide (bbc.co.uk vs hsbc.co.uk, audit F-10). Native: exact app_id
 * equality, never a substring guess that could offer the wrong credential.
 * [credentials] are password-free, so no secret is decrypted before a match.
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
 * Null for blank or malformed input, a bare public suffix, or an IP. A
 * single-label private host ("localhost") is kept for intranet matching.
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
    return host.takeIf { it.split(".").size == 1 && !psl.isListedSuffix(it) }
}

/** Never carries a password. */
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

/** Only ever called for a matched entry. */
internal fun fetchPassword(id: String): String {
    return try {
        val entryJson = RustBridge.getEntry(id)
        org.json.JSONObject(entryJson).optString("password", "")
    } catch (_: Exception) {
        ""
    }
}

data class CredentialSummary(
    val id: String,
    val username: String,
    val url: String,
    val password: String,
    val appId: String = "",
    val email: String = "",
)

/**
 * Username and email fall back to each other, so single-identifier entries
 * still fill fields that accept either.
 */
internal fun fillValueFor(kind: FieldKind, username: String, email: String): String =
    when (kind) {
        FieldKind.EMAIL -> email.ifBlank { username }
        FieldKind.USERNAME -> username.ifBlank { email }
        else -> ""
    }

/**
 * Shared by [GabbroAutofillService.buildFillResponse] and
 * [UnlockActivity.buildFillIntent] so the two paths cannot fill differently.
 * Callers guard isEmpty(): Dataset.Builder.build() rejects an empty field set.
 */
internal fun buildFillDataset(
    usernameIds: List<AutofillId>,
    emailIds: List<AutofillId>,
    passwordIds: List<AutofillId>,
    cred: CredentialSummary,
    presentation: RemoteViews,
): Dataset {
    val builder = Dataset.Builder()
    usernameIds.forEach { id ->
        val v = fillValueFor(FieldKind.USERNAME, cred.username, cred.email)
        builder.fillField(id, AutofillValue.forText(v), presentation)
    }
    emailIds.forEach { id ->
        val v = fillValueFor(FieldKind.EMAIL, cred.username, cred.email)
        builder.fillField(id, AutofillValue.forText(v), presentation)
    }
    passwordIds.forEach { id ->
        builder.fillField(id, AutofillValue.forText(cred.password), presentation)
    }
    return builder.build()
}

/**
 * `setField` exists from API 34; below that the deprecated `setValue` is the
 * only call, and dropping it would break autofill on Android 8 to 13. The one
 * gate for every fill site.
 */
internal fun Dataset.Builder.fillField(
    id: AutofillId,
    value: AutofillValue,
    presentation: RemoteViews,
) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        val field = Field.Builder()
            .setValue(value)
            .setPresentations(
                Presentations.Builder().setMenuPresentation(presentation).build(),
            )
            .build()
        setField(id, field)
    } else {
        @Suppress("DEPRECATION")
        setValue(id, value, presentation)
    }
}

/**
 * Username and email stay separate as submitted; the effective identifier is
 * resolved in the create-vs-update decision.
 */
data class CapturedLogin(
    val username: String,
    val email: String,
    val password: String,
)

/** Null without a password: nothing worth saving. First non-blank of each kind wins. */
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

/**
 * A suggestion, never a write: the user confirms (and can override) in the
 * Flutter save screen, so a save cannot silently overwrite the wrong entry.
 */
sealed class SaveDecision {
    object Create : SaveDecision()

    data class Update(val id: String) : SaveDecision()

    object NoOp : SaveDecision()
}

/**
 * Trimmed and lowercased so casing or whitespace never splits one account
 * into two (emails are case-insensitive; usernames are in practice).
 */
internal fun effectiveIdentifier(username: String, email: String): String =
    username.ifBlank { email }.trim().lowercase()

/**
 * A blank identifier never auto-targets an entry. Runs on password-free
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
 * Without a web domain or app id the entry could never be matched again, so
 * it is not worth storing.
 */
internal fun shouldOfferSave(captured: CapturedLogin?, url: String, appId: String): Boolean =
    captured != null && (url.isNotBlank() || appId.isNotBlank())

internal fun candidateLabel(summary: CredentialSummary): String =
    summary.username.ifBlank { summary.email }.ifBlank { summary.url }

/**
 * The `/autofill_save` channel payload. The password crosses to Dart because
 * the write (and its `passwordHistoryExpiry`) happens there; the match and
 * the decision stay in Kotlin.
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

/** Exact equality only; a blank app id matches nothing. */
internal fun nativeAppIdMatches(appId: String?, packageName: String?): Boolean {
    val a = appId?.trim().orEmpty()
    val p = packageName?.trim().orEmpty()
    return a.isNotEmpty() && a == p
}

enum class FieldKind { USERNAME, EMAIL, PASSWORD, NONE }

/**
 * Pure so it is testable without the framework (the `android.*` constants
 * are compile-time inlined). Tiers run most to least reliable and the first
 * match wins, so an HTML `type=password` outranks a stray "username" in the
 * field id.
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
    // Tier 1: explicit autofill hints.
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

    // Tier 2: HTML attributes, which SPAs carry in htmlInfo while leaving the
    // Android hints and inputType blank.
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

    // Tier 3: inputType bitmask.
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

    // Tier 4: keywords. html name/id count only on a real control (htmlType
    // present): a <form name="login"> container has a name but no type and
    // must not become a field. idEntry/hint stay unconditional (native apps
    // have no htmlInfo).
    val htmlFieldKeywords = if (htmlType != null) listOfNotNull(htmlName, htmlId) else emptyList()

    // A free-text hint of "password" is too noisy to trust for the password.
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

/**
 * Debug dump line for a page where `from()` finds no fields. Pure so it is
 * testable without the framework. Structural metadata only, never typed text.
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
            // S-05: the OS-attested package first; an app can shape its window
            // title, so that is only a fallback.
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
         * `adb logcat -s GabbroAutofill`. Callers gate on BuildConfig.DEBUG so
         * it is compiled out of release. Metadata only, never field values.
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
            if (webDomainOut[0] == null) {
                webDomainOut[0] = node.webDomain?.takeIf { it.isNotBlank() }
            }

            val id = node.autofillId

            if (id != null) {
                // Chromium puts the field truth (type=password, autocomplete)
                // in htmlInfo; SPAs often leave the Android hints blank.
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

/** Save-path counterpart of ParsedStructure: same classifyField, reads the typed value. */
data class CapturedSaveRequest(
    val fields: List<Pair<FieldKind, String>>,
    val webDomain: String,
    val packageName: String,
) {
    companion object {
        fun from(structure: AssistStructure): CapturedSaveRequest {
            val fields = mutableListOf<Pair<FieldKind, String>>()
            var webDomain: String? = null
            // S-05: OS-attested package first, shapeable window title as fallback.
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
