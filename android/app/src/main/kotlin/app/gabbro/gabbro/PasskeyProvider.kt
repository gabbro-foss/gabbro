package app.gabbro.gabbro

import org.json.JSONArray
import org.json.JSONObject

/**
 * PasskeyProvider — the testable core of GabbroCredentialProviderService.
 *
 * Pure functions and small classes with no service dependencies, mirroring the
 * autofill service's split: the OS-facing service stays thin, everything with
 * logic lives here where Robolectric/JVM tests can reach it without loading
 * the native library.
 */

/** One vault passkey answering a sign-in request, as parsed from RustBridge. */
internal data class PasskeyMatch(
    val entryId: String,
    val rpId: String,
    val userName: String,
    val userDisplayName: String,
    val credentialIdB64: String,
)

/** Outcome of a RustBridge passkey call. */
internal sealed class PasskeyRustResult {
    data class Matches(val matches: List<PasskeyMatch>) : PasskeyRustResult()
    object Locked : PasskeyRustResult()
    data class Error(val message: String) : PasskeyRustResult()
}

/**
 * Parse the `passkeysForRequest` JSON envelope. A locked vault is its own
 * outcome — the service turns it into an unlock action, never an empty list.
 */
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
 * The vendored privileged-browser allowlist (Google's reference list, asset
 * `passkey_privileged_browsers.json`). A caller found here may assert its own
 * web origin; everyone else must prove app identity via Digital Asset Links.
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

    /** The raw allowlist JSON is also what androidx's getOrigin() consumes. */
    companion object {
        fun normalizeFingerprint(fp: String): String = fp.uppercase().replace(":", "")
    }
}

/**
 * Does a site's Digital Asset Links file authorise this app for its
 * credentials? `assetLinksJson` is the body of
 * `https://<rpId>/.well-known/assetlinks.json`; refusal on any parse problem —
 * a site that can't vouch for the app gets no passkey.
 */
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

/** Who is asking for a passkey, and on what authority. */
internal sealed class CallerDecision {
    /** A trusted browser; use the origin it asserted and its clientDataHash. */
    object PrivilegedBrowser : CallerDecision()

    /** A native app proven by the site's asset links; origin is the apk-key-hash form. */
    data class VerifiedApp(val origin: String) : CallerDecision()

    data class Refused(val reason: String) : CallerDecision()
}

/**
 * Decide whether `packageName`/`certSha256` may operate on `rpId`'s
 * credentials. `fetchAssetLinks` returns the body of the site's
 * assetlinks.json, or null on any network/HTTP failure (which refuses —
 * fail closed).
 *
 * Consequence of a Refused: the user's passkey never signs for a caller the
 * site didn't vouch for — a lookalike app gets nothing.
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
    // F1: the toggle is the user's informed opt-in to the one network fetch —
    // off means refuse BEFORE touching the network, so zero packets without
    // consent. Browsers never reach here (offline allowlist above).
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

/**
 * The clientDataJSON the provider builds for a verified native app (privileged
 * browsers build their own). `challengeB64` comes straight from the request
 * JSON — base64url, relayed untouched.
 */
internal fun buildClientDataJson(type: String, challengeB64: String, origin: String): String {
    val o = JSONObject()
    o.put("type", type)
    o.put("challenge", challengeB64)
    o.put("origin", origin)
    return o.toString()
}

/** The `challenge` field of a WebAuthn request JSON, or null. */
internal fun challengeFromRequestJson(requestJson: String): String? =
    runCatching { JSONObject(requestJson).getString("challenge") }.getOrNull()

/**
 * Run `block` on a worker thread and wait for its result; null if it throws.
 * Android kills a network call made on the main thread
 * (NetworkOnMainThreadException), which made every native-app caller's
 * asset-links check fail — and so refused callers the site actually vouches
 * for. The wait is bounded by the block's own timeouts.
 */
internal fun <T> runOffMain(block: () -> T): T? = runCatching {
    val task = java.util.concurrent.FutureTask(block)
    Thread(task, "gabbro-offmain").start()
    task.get()
}.getOrNull()
