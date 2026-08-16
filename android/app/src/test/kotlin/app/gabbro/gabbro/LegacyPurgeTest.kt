package app.gabbro.gabbro

import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * One-shot cleanup of the removed "recently used apps" capture store. An install
 * upgraded from a build that shipped the suggestion chips still carries the
 * SharedPreferences file listing apps the user tried to log into; nothing reads it
 * any more, so it must be deleted rather than left behind as stale metadata.
 * MainActivity itself is a FlutterActivity with no test harness, hence the free
 * function.
 */
@RunWith(RobolectricTestRunner::class)
class LegacyPurgeTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
    }

    private fun stored(): String =
        context.getSharedPreferences(LEGACY_RECENT_APPS_PREFS, Context.MODE_PRIVATE)
            .getString("packages", "")
            .orEmpty()

    @Test
    fun purge_removes_an_existing_recent_apps_store() {
        context.getSharedPreferences(LEGACY_RECENT_APPS_PREFS, Context.MODE_PRIVATE)
            .edit().putString("packages", "com.company.app\ncom.other.app").apply()
        assertEquals("com.company.app\ncom.other.app", stored())

        purgeLegacyRecentApps(context)

        assertEquals("", stored())
    }

    @Test
    fun purge_is_a_noop_when_the_store_was_never_written() {
        purgeLegacyRecentApps(context)

        assertEquals("", stored())
    }

    @Test
    fun purge_is_idempotent() {
        context.getSharedPreferences(LEGACY_RECENT_APPS_PREFS, Context.MODE_PRIVATE)
            .edit().putString("packages", "com.company.app").apply()

        purgeLegacyRecentApps(context)
        purgeLegacyRecentApps(context)

        assertEquals("", stored())
    }
}
