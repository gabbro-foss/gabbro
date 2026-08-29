package app.gabbro.gabbro

import android.content.Intent
import android.net.Uri

/**
 * The system picks the app, so a link opens in the user's own browser and
 * never in a webview inside Gabbro, where the vault is open.
 */
object GabbroUrl {

    const val CHANNEL = "app.gabbro.gabbro/url"

    fun viewIntent(url: String): Intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
}
