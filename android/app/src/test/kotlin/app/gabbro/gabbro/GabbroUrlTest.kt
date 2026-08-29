package app.gabbro.gabbro

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** A wrong action or a mangled address opens the wrong thing, or nothing. */
@RunWith(RobolectricTestRunner::class)
class GabbroUrlTest {

    @Test
    fun `view intent carries the action and the address unchanged`() {
        val intent = GabbroUrl.viewIntent("https://example.com/a?b=c#d")

        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals("https://example.com/a?b=c#d", intent.data.toString())
    }

    @Test
    fun `percent-encoding is passed through untouched`() {
        // Re-encoding (%2520) or decoding to a space sends the browser elsewhere.
        val intent = GabbroUrl.viewIntent("https://example.com/x?q=a%20b")

        assertEquals("https://example.com/x?q=a%20b", intent.data.toString())
    }
}
