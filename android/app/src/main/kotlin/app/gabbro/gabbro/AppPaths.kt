package app.gabbro.gabbro

import android.content.Context

/**
 * App-support directory handed to Dart over the `paths` channel.
 * Must stay `filesDir` — exactly what path_provider_android returned —
 * or existing installs lose sight of their vaults and settings.
 */
object AppPaths {
    const val CHANNEL = "app.gabbro.gabbro/paths"

    fun appSupportDir(context: Context): String = context.filesDir.absolutePath
}
