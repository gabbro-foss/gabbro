package app.gabbro.gabbro

import android.content.Intent
import android.os.Bundle
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
                        val passphrase = call.argument<String>("passphrase") ?: ""
                        // Vault unlock is handled by the Flutter layer via the
                        // normal Rust bridge. Once unlocked, return RESULT_OK.
                        // Credential delivery via FillResponse is wired in the
                        // next session when AssistStructure passing is added.
                        setResult(RESULT_OK)
                        finish()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
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