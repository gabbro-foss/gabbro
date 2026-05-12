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
 *   3b. Vault unlocked → placeholder: return null (no suggestions yet).
 *       Real domain matching and credential Dataset construction come next session.
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
        // RustBridge is the generated JNI companion object from flutter_rust_bridge.
        // isVaultUnlocked() is a thin wrapper we will add in the next step.
        val unlocked = RustBridge.isVaultUnlocked()

        if (!unlocked) {
            callback.onSuccess(buildAuthResponse(parseResult))
            return
        }

        // Vault is unlocked — real matching logic goes here next session.
        // For now, return null (no suggestions) so the fill path compiles and runs.
        callback.onSuccess(null)
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

        val unlockIntent = Intent(this, UnlockActivity::class.java)
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
    // Companion
    // -------------------------------------------------------------------------

    companion object {
        private const val REQUEST_CODE_UNLOCK = 1001
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
) {
    fun isEmpty(): Boolean = usernameIds.isEmpty() && passwordIds.isEmpty()

    companion object {
        fun from(structure: AssistStructure): ParsedStructure {
            val usernameIds = mutableListOf<AutofillId>()
            val passwordIds = mutableListOf<AutofillId>()

            for (i in 0 until structure.windowNodeCount) {
                collectIds(structure.getWindowNodeAt(i).rootViewNode, usernameIds, passwordIds)
            }

            return ParsedStructure(usernameIds, passwordIds)
        }

        private fun collectIds(
            node: AssistStructure.ViewNode,
            usernameIds: MutableList<AutofillId>,
            passwordIds: MutableList<AutofillId>,
        ) {
            val hints = node.autofillHints
            val id = node.autofillId

            if (id != null && hints != null) {
                when {
                    hints.any { it.equals(android.view.View.AUTOFILL_HINT_USERNAME, ignoreCase = true) ||
                                it.equals(android.view.View.AUTOFILL_HINT_EMAIL_ADDRESS, ignoreCase = true) } ->
                        usernameIds.add(id)

                    hints.any { it.equals(android.view.View.AUTOFILL_HINT_PASSWORD, ignoreCase = true) } ->
                        passwordIds.add(id)
                }
            }

            for (i in 0 until node.childCount) {
                collectIds(node.getChildAt(i), usernameIds, passwordIds)
            }
        }
    }
}