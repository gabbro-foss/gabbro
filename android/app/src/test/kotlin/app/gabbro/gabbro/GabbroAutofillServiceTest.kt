package app.gabbro.gabbro

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// extractAppToken, extractRegistrableDomain, and parseSummariesJson are private
// instance methods on GabbroAutofillService (an Android Service) — they cannot
// be called from JVM unit tests without Robolectric or production-code refactoring.
// The pure-Kotlin helpers below cover the data-model layer only.

class GabbroAutofillServiceTest {

    // ── CredentialSummary ─────────────────────────────────────────────────────

    @Test
    fun credentialSummary_copy_updates_password() {
        val base = CredentialSummary(id = "x", username = "user", url = "https://a.com", password = "")
        val withPw = base.copy(password = "s3cr3t")
        assertEquals("s3cr3t", withPw.password)
        assertEquals("x", withPw.id)
        assertEquals("user", withPw.username)
    }

    @Test
    fun credentialSummary_equality_based_on_all_fields() {
        val a = CredentialSummary("1", "alice", "https://example.com", "pw")
        val b = CredentialSummary("1", "alice", "https://example.com", "pw")
        assertEquals(a, b)
    }

    // ── ParsedStructure.isEmpty ───────────────────────────────────────────────

    @Test
    fun parsedStructure_isEmpty_true_when_both_id_lists_empty() {
        val ps = ParsedStructure(
            usernameIds = emptyList(),
            passwordIds = emptyList(),
            webDomain = null,
            packageName = null,
        )
        assertTrue(ps.isEmpty())
    }

    @Test
    fun parsedStructure_isEmpty_true_even_when_webDomain_set() {
        // isEmpty only checks id lists — webDomain alone does not make it non-empty
        val ps = ParsedStructure(
            usernameIds = emptyList(),
            passwordIds = emptyList(),
            webDomain = "example.com",
            packageName = "com.example",
        )
        assertTrue(ps.isEmpty())
    }
}
