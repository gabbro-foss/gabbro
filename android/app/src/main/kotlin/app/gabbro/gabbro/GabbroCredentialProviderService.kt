package app.gabbro.gabbro

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.os.OutcomeReceiver
import androidx.annotation.RequiresApi
import androidx.credentials.exceptions.ClearCredentialUnsupportedException
import androidx.credentials.exceptions.CreateCredentialUnknownException
import androidx.credentials.exceptions.GetCredentialUnknownException
import androidx.credentials.provider.AuthenticationAction
import androidx.credentials.provider.BeginCreateCredentialRequest
import androidx.credentials.provider.BeginCreateCredentialResponse
import androidx.credentials.provider.BeginCreatePublicKeyCredentialRequest
import androidx.credentials.provider.BeginGetCredentialRequest
import androidx.credentials.provider.BeginGetCredentialResponse
import androidx.credentials.provider.BeginGetPublicKeyCredentialOption
import androidx.credentials.provider.CreateEntry
import androidx.credentials.provider.CredentialEntry
import androidx.credentials.provider.CredentialProviderService
import androidx.credentials.provider.PublicKeyCredentialEntry

/**
 * GabbroCredentialProviderService — Android's entry point into the vault for
 * passkeys. The OS binds it (API 34+) whenever an app or browser creates or
 * uses a passkey and the user has enabled Gabbro as a credential provider.
 *
 * Thin by design: query/build logic lives in PasskeyProvider.kt (testable);
 * unlock, consent, caller validation and the actual crypto happen in the
 * phase-2 activities this service points its PendingIntents at.
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class GabbroCredentialProviderService : CredentialProviderService() {

    override fun onBeginGetCredentialRequest(
        request: BeginGetCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginGetCredentialResponse, androidx.credentials.exceptions.GetCredentialException>,
    ) {
        val options = request.beginGetCredentialOptions
            .filterIsInstance<BeginGetPublicKeyCredentialOption>()
        if (options.isEmpty()) {
            callback.onError(GetCredentialUnknownException("no passkey option in request"))
            return
        }
        callback.onResult(
            buildBeginGetResponse(this, options) { RustBridge.passkeysForRequest(it) }
        )
    }

    override fun onBeginCreateCredentialRequest(
        request: BeginCreateCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginCreateCredentialResponse, androidx.credentials.exceptions.CreateCredentialException>,
    ) {
        if (request !is BeginCreatePublicKeyCredentialRequest) {
            callback.onError(CreateCredentialUnknownException("only passkeys are supported"))
            return
        }
        callback.onResult(buildBeginCreateResponse(this))
    }

    override fun onClearCredentialStateRequest(
        request: androidx.credentials.provider.ProviderClearCredentialStateRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<Void?, androidx.credentials.exceptions.ClearCredentialException>,
    ) {
        // Nothing cached outside the vault; sign-out state lives with the RP.
        callback.onError(ClearCredentialUnsupportedException())
    }
}

/** Distinct request codes per entry keep every PendingIntent unique. */
private var nextRequestCode = 1000

private fun pendingIntentFor(context: Context, cls: Class<*>, entryId: String?): PendingIntent {
    val intent = Intent(context, cls)
    if (entryId != null) intent.putExtra(GabbroPasskeyActivity.EXTRA_ENTRY_ID, entryId)
    return PendingIntent.getActivity(
        context,
        nextRequestCode++,
        intent,
        PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}

/**
 * The picker rows for a sign-in request. Locked vault -> a single unlock
 * action (never an empty list, which would read as "no passkeys here" and
 * push the user to a rival provider); unlocked -> one row per match.
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
internal fun buildBeginGetResponse(
    context: Context,
    options: List<BeginGetPublicKeyCredentialOption>,
    rustMatches: (String) -> String,
): BeginGetCredentialResponse {
    val entries = ArrayList<CredentialEntry>()
    for (option in options) {
        when (val result = parsePasskeyMatches(rustMatches(option.requestJson))) {
            is PasskeyRustResult.Locked -> {
                return BeginGetCredentialResponse(
                    authenticationActions = listOf(
                        AuthenticationAction(
                            title = context.getString(R.string.passkey_unlock_label),
                            pendingIntent = pendingIntentFor(
                                context, GabbroPasskeyGetActivity::class.java, null
                            ),
                        )
                    ),
                )
            }
            is PasskeyRustResult.Matches -> {
                for (m in result.matches) {
                    entries.add(
                        PublicKeyCredentialEntry.Builder(
                            context,
                            m.userName,
                            pendingIntentFor(context, GabbroPasskeyGetActivity::class.java, m.entryId),
                            option,
                        )
                            .setDisplayName(m.userDisplayName)
                            .build()
                    )
                }
            }
            is PasskeyRustResult.Error -> {
                // A malformed request yields no rows; other options may still match.
            }
        }
    }
    return BeginGetCredentialResponse(credentialEntries = entries)
}

/** The single "Save passkey in Gabbro" row for a creation request. */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
internal fun buildBeginCreateResponse(context: Context): BeginCreateCredentialResponse =
    BeginCreateCredentialResponse(
        createEntries = listOf(
            CreateEntry(
                accountName = context.getString(R.string.passkey_save_label),
                pendingIntent = pendingIntentFor(
                    context, GabbroPasskeyCreateActivity::class.java, null
                ),
            )
        ),
    )
