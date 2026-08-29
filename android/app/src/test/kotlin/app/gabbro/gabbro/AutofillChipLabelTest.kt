package app.gabbro.gabbro

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * The chip is a RemoteViews drawn by the system UI, so its text comes from
 * res/values-XX/ resolved against the device locale, never the Flutter ARBs
 * or the in-app language override.
 */
@RunWith(RobolectricTestRunner::class)
class AutofillChipLabelTest {

    private fun label(qualifiers: String): String {
        RuntimeEnvironment.setQualifiers(qualifiers)
        return RuntimeEnvironment.getApplication().getString(R.string.autofill_unlock_label)
    }

    @Test
    fun default_locale_is_english() {
        assertEquals("Unlock Gabbro to autofill", label("+en"))
    }

    @Test
    fun translated_locale_differs_from_english() {
        assertNotEquals(
            "values-de must override the English label",
            label("+en"),
            label("+de"),
        )
    }

    @Test
    fun serbian_scripts_resolve_distinctly() {
        assertNotEquals(
            "values-b+sr+Latn (Latin) must differ from Cyrillic values-b+sr",
            label("+b+sr"),
            label("+b+sr+Latn"),
        )
    }

    @Test
    fun every_supported_locale_has_a_nonblank_label() {
        for (q in SUPPORTED_QUALIFIERS) {
            val s = label("+$q")
            assertTrue("locale $q resolves a blank autofill_unlock_label", s.isNotBlank())
        }
    }

    companion object {
        // Every ARB locale. Variants with identical chip text share the base
        // folder; only zh-TW and sr-Latn carry their own.
        private val SUPPORTED_QUALIFIERS = listOf(
            "bg", "cs", "da", "de", "el", "en", "es", "et", "eu", "fi", "fr",
            "hr", "hu", "it", "ja", "kk", "ko", "lt", "lv", "nb", "nl", "nn",
            "pl", "pt", "b+pt+BR", "b+pt+PT", "ru", "sk", "sl", "b+sr",
            "b+sr+Latn", "sv", "uk", "yo", "zh", "b+zh+CN", "b+zh+TW",
        )
    }
}
