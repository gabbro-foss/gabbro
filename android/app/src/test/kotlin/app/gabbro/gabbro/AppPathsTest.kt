package app.gabbro.gabbro

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * Pins the app-support directory the `app.gabbro.gabbro/paths` channel hands
 * to Dart: it must be `filesDir` — exactly what path_provider_android
 * returned — or every existing install loses sight of its vaults.
 */
@RunWith(RobolectricTestRunner::class)
class AppPathsTest {

    @Test
    fun `appSupportDir is the context filesDir`() {
        val context = RuntimeEnvironment.getApplication()
        assertEquals(
            context.filesDir.absolutePath,
            AppPaths.appSupportDir(context),
        )
    }

    @Test
    fun `appSupportDir is a non-empty absolute path`() {
        val dir = AppPaths.appSupportDir(RuntimeEnvironment.getApplication())
        assertTrue(dir.isNotEmpty())
        assertTrue(dir.startsWith("/"))
    }
}
