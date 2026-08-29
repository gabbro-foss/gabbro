package app.gabbro.gabbro

import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/** Nothing reads the store any more; left behind it lists the apps the user logged into. */
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
