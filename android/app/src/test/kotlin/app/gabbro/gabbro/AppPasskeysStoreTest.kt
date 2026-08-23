package app.gabbro.gabbro

import android.content.Context
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * The mirrored app-passkeys opt-in (F1). The credential provider runs without
 * Flutter, so this SharedPreferences slot — written over the app_passkeys
 * channel — is the only place it can read the toggle. Absent must mean OFF:
 * a fresh install refuses native-app passkeys until the user opts in.
 */
@RunWith(RobolectricTestRunner::class)
class AppPasskeysStoreTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("gabbro_app_passkeys", Context.MODE_PRIVATE)
            .edit().clear().apply()
    }

    @Test
    fun absent_flag_means_disabled() {
        assertFalse(AppPasskeysStore.enabled(context))
    }

    @Test
    fun set_true_round_trips() {
        AppPasskeysStore.set(context, true)
        assertTrue(AppPasskeysStore.enabled(context))
    }

    @Test
    fun set_false_after_true_disables() {
        AppPasskeysStore.set(context, true)
        AppPasskeysStore.set(context, false)
        assertFalse(AppPasskeysStore.enabled(context))
    }
}
