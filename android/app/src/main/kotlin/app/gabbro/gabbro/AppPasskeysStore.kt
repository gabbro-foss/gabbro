package app.gabbro.gabbro

import android.content.Context

/**
 * The mirrored app-passkeys opt-in (F1). Dart owns the setting
 * (settings.jsonc) and pushes changes over the app_passkeys channel; the
 * credential provider runs without Flutter, so this SharedPreferences slot is
 * the only place it can read the toggle. Absent means OFF — a fresh install
 * refuses native-app passkeys until the user opts in.
 */
object AppPasskeysStore {
    private const val PREFS_FILE = "gabbro_app_passkeys"
    private const val KEY_ENABLED = "enabled"

    fun set(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun enabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, false)
}
