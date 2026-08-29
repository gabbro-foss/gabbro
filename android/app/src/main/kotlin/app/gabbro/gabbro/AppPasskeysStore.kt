package app.gabbro.gabbro

import android.content.Context

/**
 * Dart owns the F1 toggle (settings.jsonc); the credential provider runs
 * without Flutter, so this mirror is the only place it can read it. Absent
 * means off: a fresh install refuses native-app passkeys until opted in.
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
