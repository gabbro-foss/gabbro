package app.gabbro.gabbro

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Pins what the `app.gabbro.gabbro/url` channel hands to Android: a plain view
 * request for exactly the address the user was shown, so the system's own
 * chooser picks the browser. Anything else — a wrong action, a mangled
 * address — and the link either opens the wrong thing or nothing at all.
 */
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
        // Re-encoding it (%2520) or decoding it to a space would send the
        // browser somewhere other than the address the user was shown.
        val intent = GabbroUrl.viewIntent("https://example.com/x?q=a%20b")

        assertEquals("https://example.com/x?q=a%20b", intent.data.toString())
    }
}
