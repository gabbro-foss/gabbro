package app.gabbro.gabbro

import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.util.Log
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
 * Runs the Flutter unlock and consent UI for a picker tap, then the subclass
 * performs the operation via RustBridge. Caller validation happens here,
 * before any crypto, so the vault never signs for a caller the relying party
 * did not authorise.
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
abstract class GabbroPasskeyActivity : GabbroUnlockHostActivity() {

    companion object {
        const val EXTRA_ENTRY_ID = "app.gabbro.gabbro.EXTRA_PASSKEY_ENTRY_ID"

        // An in-flow unlock leaves the session open; rows rebuilt after it
        // carry this so their get flow relocks, leaving Gabbro as the user
        // left it.
        const val EXTRA_RELOCK_AFTER = "app.gabbro.gabbro.EXTRA_PASSKEY_RELOCK_AFTER"
        private const val CHANNEL = "app.gabbro.gabbro/passkey"

        // Caller identity, branch and refusal reason are public material;
        // never log request JSON or user names.
        internal const val TAG = "GabbroPasskey"
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
                Log.i(TAG, "channel: ${call.method}")
                when (call.method) {
                    "isUnlocked" -> result.success(RustBridge.isVaultUnlocked())
                    "getRequestInfo" -> result.success(requestInfo())
                    // Sets the OS result without finishing: Dart may still
                    // have to lock a session this activity opened (RT-5),
                    // then calls "finish".
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

    /** {"mode": "create"|"get"|"unlock", "rpId", "userName"} for the consent line. */
    protected abstract fun requestInfo(): Map<String, String>

    /** Validates the caller, runs the RustBridge operation, sets the result. */
    protected abstract fun performOperation()

    protected abstract fun refuse(reason: String)

    /** Colon-hex, the form the allowlist and asset links use. */
    protected fun callerCertSha256(info: CallingAppInfo): String? {
        val signatures = info.signingInfo.apkContentsSigners
        val first = signatures.firstOrNull() ?: return null
        val digest = MessageDigest.getInstance("SHA-256").digest(first.toByteArray())
        return digest.joinToString(":") { "%02X".format(it) }
    }

    /** The android:apk-key-hash origin form. */
    protected fun callerApkKeyHashB64(info: CallingAppInfo): String? {
        val first = info.signingInfo.apkContentsSigners.firstOrNull() ?: return null
        val digest = MessageDigest.getInstance("SHA-256").digest(first.toByteArray())
        return Base64.encodeToString(digest, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }

    /** Null on any failure, which refuses. */
    protected fun fetchAssetLinks(url: String): String? = runOffMain {
        val conn = java.net.URL(url).openConnection() as HttpsURLConnection
        conn.connectTimeout = 5000
        conn.readTimeout = 5000
        conn.inputStream.bufferedReader().use { it.readText() }
    }
}

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
        Log.i(TAG, "create onCreate: caller=${provider.callingAppInfo.packageName} cdh=${clientDataHash != null}")
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
        Log.i(
            TAG,
            "create op: caller=${info.packageName} cert=$cert " +
                "privileged=${allowlist.isPrivileged(info.packageName, cert)} " +
                "cdh=${clientDataHash != null} rpId=$rpId",
        )
        val responseJson: String
        if (clientDataHash != null && allowlist.isPrivileged(info.packageName, cert)) {
            responseJson = RustBridge.registerPasskey(requestJson, null)
        } else {
            val keyHash = callerApkKeyHashB64(info) ?: return refuse("caller certificate unreadable")
            when (val decision = decideCaller(
                rpId, info.packageName, cert, allowlist, keyHash,
                AppPasskeysStore.enabled(this), ::fetchAssetLinks
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
        Log.i(TAG, "create result set (${responseJson.length} chars)")
    }

    override fun refuse(reason: String) {
        Log.i(TAG, "create refuse: $reason")
        val result = android.content.Intent()
        PendingIntentHandler.setCreateCredentialException(
            result, CreateCredentialUnknownException(reason)
        )
        setResult(RESULT_OK, result)
        finish()
    }
}

@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class GabbroPasskeyGetActivity : GabbroPasskeyActivity() {

    private var requestJson: String = ""
    private var clientDataHash: ByteArray? = null
    private var callingAppInfo: CallingAppInfo? = null

    // The picker's unlock action carries only the begin request, so this
    // activity can hand back rebuilt rows but never a signed credential.
    private var unlockMode = false
    private var beginOptions: List<androidx.credentials.provider.BeginGetPublicKeyCredentialOption> =
        emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val provider = PendingIntentHandler.retrieveProviderGetCredentialRequest(intent)
        if (provider == null) {
            val begin = PendingIntentHandler.retrieveBeginGetCredentialRequest(intent)
            val options = begin?.beginGetCredentialOptions
                ?.filterIsInstance<androidx.credentials.provider.BeginGetPublicKeyCredentialOption>()
            if (options.isNullOrEmpty()) {
                refuse("no get request in intent")
                return
            }
            unlockMode = true
            beginOptions = options
            Log.i(TAG, "get onCreate: unlock mode, ${options.size} option(s)")
            return
        }
        val option = provider.credentialOptions
            .filterIsInstance<GetPublicKeyCredentialOption>()
            .firstOrNull()
        if (option == null) {
            refuse("no get request in intent")
            return
        }
        requestJson = option.requestJson
        clientDataHash = option.clientDataHash
        callingAppInfo = provider.callingAppInfo
        Log.i(TAG, "get onCreate: caller=${provider.callingAppInfo.packageName} cdh=${clientDataHash != null}")
    }

    override fun requestInfo(): Map<String, String> =
        if (unlockMode) mapOf("mode" to "unlock", "rpId" to "", "userName" to "")
        else mapOf(
            "mode" to "get",
            "rpId" to (runCatching {
                org.json.JSONObject(requestJson).getString("rpId")
            }.getOrNull() ?: ""),
            "userName" to "",
            "relockAfter" to intent.getBooleanExtra(EXTRA_RELOCK_AFTER, false).toString(),
        )

    private fun performUnlockRefresh() {
        val response = buildBeginGetResponse(this, beginOptions, relockAfter = true) {
            RustBridge.passkeysForRequest(it)
        }
        val result = android.content.Intent()
        PendingIntentHandler.setBeginGetCredentialResponse(result, response)
        setResult(RESULT_OK, result)
        Log.i(TAG, "unlock result set: ${response.credentialEntries.size} row(s)")
    }

    override fun performOperation() {
        if (unlockMode) return performUnlockRefresh()
        val info = callingAppInfo ?: return refuse("caller unknown")
        val cert = callerCertSha256(info) ?: return refuse("caller certificate unreadable")
        val rpId = requestInfo()["rpId"].orEmpty()
        Log.i(
            TAG,
            "get op: caller=${info.packageName} cert=$cert " +
                "privileged=${allowlist.isPrivileged(info.packageName, cert)} " +
                "cdh=${clientDataHash != null} rpId=$rpId",
        )

        // A picker tap carries the entry; the unlock path has to re-query.
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
                rpId, info.packageName, cert, allowlist, keyHash,
                AppPasskeysStore.enabled(this), ::fetchAssetLinks
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
        Log.i(TAG, "get result set (${responseJson.length} chars)")
    }

    override fun refuse(reason: String) {
        Log.i(TAG, "get refuse: $reason")
        if (unlockMode) {
            // No get request to answer; a cancel keeps the picker usable.
            setResult(RESULT_CANCELED)
            finish()
            return
        }
        val result = android.content.Intent()
        PendingIntentHandler.setGetCredentialException(
            result, GetCredentialUnknownException(reason)
        )
        setResult(RESULT_OK, result)
        finish()
    }
}
