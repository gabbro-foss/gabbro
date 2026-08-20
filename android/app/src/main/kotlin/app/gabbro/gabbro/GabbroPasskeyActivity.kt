package app.gabbro.gabbro

import android.os.Build
import android.os.Bundle
import android.util.Base64
import androidx.annotation.RequiresApi
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.CreateCredentialUnknownException
import androidx.credentials.exceptions.GetCredentialUnknownException
import androidx.credentials.provider.CallingAppInfo
import androidx.credentials.provider.PendingIntentHandler
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import javax.net.ssl.HttpsURLConnection

/**
 * Phase 2 of the passkey flows: the OS routes the user's picker tap here.
 * Runs the Flutter unlock/consent UI (passkeyUnlockMain entrypoint); once Dart
 * reports the vault is unlocked and the user consented, the subclass performs
 * the operation via RustBridge and hands the result back to the OS.
 *
 * Caller validation happens HERE, before any crypto: a privileged browser may
 * assert its own web origin; a native app must be vouched for by the site's
 * Digital Asset Links file. Anyone else is refused — the vault never signs
 * for a caller the relying party didn't authorise.
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
abstract class GabbroPasskeyActivity : GabbroUnlockHostActivity() {

    companion object {
        const val EXTRA_ENTRY_ID = "app.gabbro.gabbro.EXTRA_PASSKEY_ENTRY_ID"
        private const val CHANNEL = "app.gabbro.gabbro/passkey"
    }

    internal val allowlist: PrivilegedBrowserAllowlist by lazy {
        PrivilegedBrowserAllowlist(
            assets.open("passkey_privileged_browsers.json").bufferedReader().use { it.readText() }
        )
    }

    override fun getDartEntrypointFunctionName(): String = "passkeyUnlockMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isUnlocked" -> result.success(RustBridge.isVaultUnlocked())
                    // Dart asks what to show on the consent line.
                    "getRequestInfo" -> result.success(requestInfo())
                    // Dart: vault is unlocked and the user approved. Sets the
                    // OS result but does NOT finish — Dart may still need to
                    // lock a session this activity opened (see RT-5 in the
                    // autofill unlock flow), then calls "finish".
                    "approve" -> {
                        performOperation()
                        result.success(null)
                    }
                    "finish" -> {
                        finish()
                        result.success(null)
                    }
                    "cancel" -> {
                        refuse("cancelled by user")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** {"mode": "create"|"get", "rpId": ..., "userName": ...} for the Dart UI. */
    protected abstract fun requestInfo(): Map<String, String>

    /** Validate the caller, run the RustBridge operation, set the result, finish. */
    protected abstract fun performOperation()

    /** Finish with the flow-appropriate failure result. */
    protected abstract fun refuse(reason: String)

    /** SHA-256 of the caller's signing cert, colon-hex, or null if unreadable. */
    protected fun callerCertSha256(info: CallingAppInfo): String? {
        val signatures = info.signingInfo.apkContentsSigners
        val first = signatures.firstOrNull() ?: return null
        val digest = MessageDigest.getInstance("SHA-256").digest(first.toByteArray())
        return digest.joinToString(":") { "%02X".format(it) }
    }

    /** base64url(SHA-256 of signing cert) — the android origin key hash form. */
    protected fun callerApkKeyHashB64(info: CallingAppInfo): String? {
        val first = info.signingInfo.apkContentsSigners.firstOrNull() ?: return null
        val digest = MessageDigest.getInstance("SHA-256").digest(first.toByteArray())
        return Base64.encodeToString(digest, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }

    /** Blocking fetch of a site's assetlinks.json; null on any failure (refuses). */
    protected fun fetchAssetLinks(url: String): String? = runCatching {
        val conn = java.net.URL(url).openConnection() as HttpsURLConnection
        conn.connectTimeout = 5000
        conn.readTimeout = 5000
        conn.inputStream.bufferedReader().use { it.readText() }
    }.getOrNull()
}

/** Creation flow: mint + store, return the registration response. */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class GabbroPasskeyCreateActivity : GabbroPasskeyActivity() {

    private var requestJson: String = ""
    private var clientDataHash: ByteArray? = null
    private var callingAppInfo: CallingAppInfo? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val provider = PendingIntentHandler.retrieveProviderCreateCredentialRequest(intent)
        val request = provider?.callingRequest as? CreatePublicKeyCredentialRequest
        if (provider == null || request == null) {
            refuse("no create request in intent")
            return
        }
        requestJson = request.requestJson
        clientDataHash = request.clientDataHash
        callingAppInfo = provider.callingAppInfo
    }

    override fun requestInfo(): Map<String, String> = mapOf(
        "mode" to "create",
        "rpId" to (runCatching {
            org.json.JSONObject(requestJson).getJSONObject("rp").getString("id")
        }.getOrNull() ?: ""),
        "userName" to (runCatching {
            org.json.JSONObject(requestJson).getJSONObject("user").getString("name")
        }.getOrNull() ?: ""),
    )

    override fun performOperation() {
        val info = callingAppInfo ?: return refuse("caller unknown")
        val cert = callerCertSha256(info) ?: return refuse("caller certificate unreadable")
        val rpId = requestInfo()["rpId"].orEmpty()
        val responseJson: String
        if (clientDataHash != null && allowlist.isPrivileged(info.packageName, cert)) {
            // Privileged browser: it attaches its own clientDataJSON.
            responseJson = RustBridge.registerPasskey(requestJson, null)
        } else {
            val keyHash = callerApkKeyHashB64(info) ?: return refuse("caller certificate unreadable")
            when (val decision = decideCaller(
                rpId, info.packageName, cert, allowlist, keyHash, ::fetchAssetLinks
            )) {
                is CallerDecision.Refused -> return refuse(decision.reason)
                is CallerDecision.PrivilegedBrowser -> return refuse(
                    "privileged browser sent no clientDataHash"
                )
                is CallerDecision.VerifiedApp -> {
                    val challenge = challengeFromRequestJson(requestJson)
                        ?: return refuse("request carries no challenge")
                    val cdj = buildClientDataJson("webauthn.create", challenge, decision.origin)
                    val cdjB64 = Base64.encodeToString(
                        cdj.toByteArray(),
                        Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
                    )
                    responseJson = RustBridge.registerPasskey(requestJson, cdjB64)
                }
            }
        }
        if (org.json.JSONObject(responseJson).has("error")) {
            return refuse(org.json.JSONObject(responseJson).getString("error"))
        }
        val result = android.content.Intent()
        PendingIntentHandler.setCreateCredentialResponse(
            result, CreatePublicKeyCredentialResponse(responseJson)
        )
        setResult(RESULT_OK, result)
        // No finish() here: Dart locks a session it opened, then calls "finish".
    }

    override fun refuse(reason: String) {
        val result = android.content.Intent()
        PendingIntentHandler.setCreateCredentialException(
            result, CreateCredentialUnknownException(reason)
        )
        setResult(RESULT_OK, result)
        finish()
    }
}

/** Sign-in flow: sign the challenge with the picked (or only) credential. */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class GabbroPasskeyGetActivity : GabbroPasskeyActivity() {

    private var requestJson: String = ""
    private var clientDataHash: ByteArray? = null
    private var callingAppInfo: CallingAppInfo? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val provider = PendingIntentHandler.retrieveProviderGetCredentialRequest(intent)
        val option = provider?.credentialOptions
            ?.filterIsInstance<GetPublicKeyCredentialOption>()
            ?.firstOrNull()
        if (provider == null || option == null) {
            refuse("no get request in intent")
            return
        }
        requestJson = option.requestJson
        clientDataHash = option.clientDataHash
        callingAppInfo = provider.callingAppInfo
    }

    override fun requestInfo(): Map<String, String> = mapOf(
        "mode" to "get",
        "rpId" to (runCatching {
            org.json.JSONObject(requestJson).getString("rpId")
        }.getOrNull() ?: ""),
        "userName" to "",
    )

    override fun performOperation() {
        val info = callingAppInfo ?: return refuse("caller unknown")
        val cert = callerCertSha256(info) ?: return refuse("caller certificate unreadable")
        val rpId = requestInfo()["rpId"].orEmpty()

        // Resolve the entry: the picker tap carries it; the unlock path re-queries.
        val entryId = intent.getStringExtra(EXTRA_ENTRY_ID) ?: run {
            val parsed = parsePasskeyMatches(RustBridge.passkeysForRequest(requestJson))
            (parsed as? PasskeyRustResult.Matches)?.matches?.firstOrNull()?.entryId
                ?: return refuse("no matching passkey")
        }

        val responseJson: String
        if (clientDataHash != null && allowlist.isPrivileged(info.packageName, cert)) {
            val hashB64 = Base64.encodeToString(
                clientDataHash, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP
            )
            responseJson = RustBridge.signPasskeyAssertion(entryId, null, hashB64)
        } else {
            val keyHash = callerApkKeyHashB64(info) ?: return refuse("caller certificate unreadable")
            when (val decision = decideCaller(
                rpId, info.packageName, cert, allowlist, keyHash, ::fetchAssetLinks
            )) {
                is CallerDecision.Refused -> return refuse(decision.reason)
                is CallerDecision.PrivilegedBrowser -> return refuse(
                    "privileged browser sent no clientDataHash"
                )
                is CallerDecision.VerifiedApp -> {
                    val challenge = challengeFromRequestJson(requestJson)
                        ?: return refuse("request carries no challenge")
                    val cdj = buildClientDataJson("webauthn.get", challenge, decision.origin)
                    val cdjB64 = Base64.encodeToString(
                        cdj.toByteArray(),
                        Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
                    )
                    responseJson = RustBridge.signPasskeyAssertion(entryId, cdjB64, null)
                }
            }
        }
        if (org.json.JSONObject(responseJson).has("error")) {
            return refuse(org.json.JSONObject(responseJson).getString("error"))
        }
        val result = android.content.Intent()
        PendingIntentHandler.setGetCredentialResponse(
            result, GetCredentialResponse(PublicKeyCredential(responseJson))
        )
        setResult(RESULT_OK, result)
        // No finish() here: Dart locks a session it opened, then calls "finish".
    }

    override fun refuse(reason: String) {
        val result = android.content.Intent()
        PendingIntentHandler.setGetCredentialException(
            result, GetCredentialUnknownException(reason)
        )
        setResult(RESULT_OK, result)
        finish()
    }
}
