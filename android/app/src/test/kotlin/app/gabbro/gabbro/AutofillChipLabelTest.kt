package app.gabbro.gabbro

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * Guards localization of the autofill suggestion chip (autofill_unlock_label).
 *
 * The chip is a RemoteViews rendered by the system UI, so it has no Flutter
 * engine and cannot read the Flutter ARBs — its text comes from Android string
 * resources (res/values-XX/), resolved by the OS against the DEVICE locale.
 * These tests pin that every supported locale resolves a non-blank label and
 * that the translated folders actually wire up (no silent fallback to English).
 *
 * Caveat (not testable, documented in ARCHITECTURE.md): the OS picks the folder
 * by device locale, never by Gabbro's in-app language override.
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
        // Cyrillic base vs Latin script variant must not collapse to one folder.
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
        // Android resource qualifiers for every locale Gabbro's ARBs support.
        // Region/script variants fall back to their base folder where the chip
        // text is identical (pt-BR/pt-PT -> pt, zh-CN -> zh); only zh-TW and
        // sr-Latn carry their own folder.
        private val SUPPORTED_QUALIFIERS = listOf(
            "bg", "cs", "da", "de", "el", "en", "es", "et", "eu", "fi", "fr",
            "hr", "hu", "it", "ja", "kk", "ko", "lt", "lv", "nb", "nl", "nn",
            "pl", "pt", "b+pt+BR", "b+pt+PT", "ru", "sk", "sl", "b+sr",
            "b+sr+Latn", "sv", "uk", "yo", "zh", "b+zh+CN", "b+zh+TW",
        )
    }
}
