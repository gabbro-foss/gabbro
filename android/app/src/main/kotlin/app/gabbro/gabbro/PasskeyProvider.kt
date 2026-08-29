package app.gabbro.gabbro

import org.json.JSONArray
import org.json.JSONObject

// The logic behind GabbroCredentialProviderService, kept free of service
// dependencies so JVM tests reach it without loading the native library.

internal data class PasskeyMatch(
    val entryId: String,
    val rpId: String,
    val userName: String,
    val userDisplayName: String,
    val credentialIdB64: String,
)

internal sealed class PasskeyRustResult {
    data class Matches(val matches: List<PasskeyMatch>) : PasskeyRustResult()
    object Locked : PasskeyRustResult()
    data class Error(val message: String) : PasskeyRustResult()
}

/** A locked vault is its own outcome: the service offers unlock, never an empty list. */
internal fun parsePasskeyMatches(json: String): PasskeyRustResult {
    val obj = runCatching { JSONObject(json) }.getOrNull()
        ?: return PasskeyRustResult.Error("unparseable bridge reply")
    val error = obj.optString("error")
    if (error.isNotEmpty()) {
        return if (error.contains("locked")) PasskeyRustResult.Locked
        else PasskeyRustResult.Error(error)
    }
    val arr = obj.optJSONArray("matches") ?: JSONArray()
    val out = ArrayList<PasskeyMatch>(arr.length())
    for (i in 0 until arr.length()) {
        val m = arr.getJSONObject(i)
        out.add(
            PasskeyMatch(
                entryId = m.getString("entryId"),
                rpId = m.getString("rpId"),
                userName = m.getString("userName"),
                userDisplayName = m.getString("userDisplayName"),
                credentialIdB64 = m.getString("credentialIdB64"),
            )
        )
    }
    return PasskeyRustResult.Matches(out)
}

/**
 * Google's reference list, vendored as `passkey_privileged_browsers.json`. A
 * browser found here may assert its own web origin; every other caller must
 * prove app identity via Digital Asset Links.
 */
internal class PrivilegedBrowserAllowlist(json: String) {
    private val fingerprintsByPackage: Map<String, Set<String>> = buildMap {
        val apps = JSONObject(json).getJSONArray("apps")
        for (i in 0 until apps.length()) {
            val info = apps.getJSONObject(i).getJSONObject("info")
            val pkg = info.getString("package_name")
            val prints = HashSet<String>()
            val sigs = info.getJSONArray("signatures")
            for (j in 0 until sigs.length()) {
                prints.add(normalizeFingerprint(sigs.getJSONObject(j).getString("cert_fingerprint_sha256")))
            }
            put(pkg, (get(pkg) ?: emptySet()) + prints)
        }
    }

    fun isPrivileged(packageName: String, certSha256: String): Boolean =
        fingerprintsByPackage[packageName]?.contains(normalizeFingerprint(certSha256)) == true

    companion object {
        fun normalizeFingerprint(fp: String): String = fp.uppercase().replace(":", "")
    }
}

/** Any parse problem refuses: a site that cannot vouch for the app gets no passkey. */
internal fun assetLinksPermitsApp(
    assetLinksJson: String,
    packageName: String,
    certSha256: String,
): Boolean {
    val statements = runCatching { JSONArray(assetLinksJson) }.getOrNull() ?: return false
    val wanted = PrivilegedBrowserAllowlist.normalizeFingerprint(certSha256)
    for (i in 0 until statements.length()) {
        val st = statements.optJSONObject(i) ?: continue
        val relations = st.optJSONArray("relation") ?: continue
        var related = false
        for (r in 0 until relations.length()) {
            val rel = relations.optString(r)
            if (rel == "delegate_permission/common.handle_all_urls" ||
                rel == "delegate_permission/common.get_login_creds"
            ) {
                related = true
            }
        }
        if (!related) continue
        val target = st.optJSONObject("target") ?: continue
        if (target.optString("namespace") != "android_app") continue
        if (target.optString("package_name") != packageName) continue
        val prints = target.optJSONArray("sha256_cert_fingerprints") ?: continue
        for (p in 0 until prints.length()) {
            if (PrivilegedBrowserAllowlist.normalizeFingerprint(prints.optString(p)) == wanted) {
                return true
            }
        }
    }
    return false
}

internal sealed class CallerDecision {
    /** Uses the origin the browser asserted and its own clientDataHash. */
    object PrivilegedBrowser : CallerDecision()

    /** Origin is the apk-key-hash form. */
    data class VerifiedApp(val origin: String) : CallerDecision()

    data class Refused(val reason: String) : CallerDecision()
}

/**
 * Fails closed: a null `fetchAssetLinks` (any network or HTTP failure)
 * refuses, so a lookalike app the site never vouched for gets no signature.
 */
internal fun decideCaller(
    rpId: String,
    packageName: String,
    certSha256: String,
    allowlist: PrivilegedBrowserAllowlist,
    apkKeyHashB64: String,
    appPasskeysEnabled: Boolean,
    fetchAssetLinks: (String) -> String?,
): CallerDecision {
    if (allowlist.isPrivileged(packageName, certSha256)) {
        return CallerDecision.PrivilegedBrowser
    }
    // F1: the toggle is the opt-in to the one network fetch, so off refuses
    // before any packet is sent. Browsers never reach here.
    if (!appPasskeysEnabled) {
        return CallerDecision.Refused("app passkeys are disabled in settings")
    }
    val body = fetchAssetLinks("https://$rpId/.well-known/assetlinks.json")
        ?: return CallerDecision.Refused("could not fetch asset links for $rpId")
    return if (assetLinksPermitsApp(body, packageName, certSha256)) {
        CallerDecision.VerifiedApp(origin = "android:apk-key-hash:$apkKeyHashB64")
    } else {
        CallerDecision.Refused("$rpId does not vouch for $packageName")
    }
}

/** For verified native apps only; privileged browsers build their own. Challenge relayed untouched. */
internal fun buildClientDataJson(type: String, challengeB64: String, origin: String): String {
    val o = JSONObject()
    o.put("type", type)
    o.put("challenge", challengeB64)
    o.put("origin", origin)
    return o.toString()
}

internal fun challengeFromRequestJson(requestJson: String): String? =
    runCatching { JSONObject(requestJson).getString("challenge") }.getOrNull()

/**
 * Android throws NetworkOnMainThreadException for a fetch on the main thread,
 * which would refuse every native-app caller. The wait is bounded by the
 * block's own timeouts.
 */
internal fun <T> runOffMain(block: () -> T): T? = runCatching {
    val task = java.util.concurrent.FutureTask(block)
    Thread(task, "gabbro-offmain").start()
    task.get()
}.getOrNull()
