package app.gabbro.gabbro

import android.app.assist.AssistStructure
import android.content.Intent
import android.os.Bundle
import android.service.autofill.FillResponse
import io.flutter.embedding.android.FlutterActivity

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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The Flutter route is rendered by FlutterActivity automatically
        // once the engine is warm. The initial route is set via the manifest
        // or overridden below. The /autofill-unlock route will be wired in
        // the Flutter session that follows this Kotlin skeleton session.
    }

    /**
     * Called by the Flutter layer (via MethodChannel, wired next session)
     * when the user has successfully entered their passphrase and the vault
     * is confirmed unlocked.
     *
     * [credential] — a map with keys "username" and "password" (either may
     * be null if the target screen only had one field type).
     *
     * Packages the credential into a FillResponse and returns it to the OS.
     */
    fun onVaultUnlocked(credential: Map<String, String?>) {
        // FillResponse construction with real AutofillIds requires the
        // AssistStructure from the original fill request — passed via the
        // intent in a later session. Placeholder result for now.
        setResult(RESULT_OK, Intent().apply {
            // Real FillResponse delivered here once MethodChannel is wired.
            // For now RESULT_OK is never actually reached from Flutter
            // because the /autofill-unlock route does not yet exist.
        })
        finish()
    }

    /**
     * User pressed back or cancelled the unlock flow.
     * RESULT_CANCELED tells the OS to deliver nothing to the target field.
     */
    override fun onBackPressed() {
        setResult(RESULT_CANCELED)
        finish()
    }

    override fun getInitialRoute(): String = "/autofill-unlock"
}