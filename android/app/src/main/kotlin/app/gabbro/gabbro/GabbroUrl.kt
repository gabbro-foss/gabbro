package app.gabbro.gabbro

import android.content.Intent
import android.net.Uri

/**
 * The link side of the `app.gabbro.gabbro/url` channel.
 *
 * Gabbro asks Android to view the address and lets the system pick the app,
 * so a link always opens in the user's own browser and never in a webview
 * inside Gabbro, where the vault is open.
 *
 * Replaces the `url_launcher` plugin's Android side.
 */
object GabbroUrl {

    const val CHANNEL = "app.gabbro.gabbro/url"

    /** A view request for [url], exactly as the user was shown it. */
    fun viewIntent(url: String): Intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
}
