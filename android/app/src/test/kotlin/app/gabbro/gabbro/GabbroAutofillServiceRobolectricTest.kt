package app.gabbro.gabbro

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

/**
 * Robolectric-backed tests for the autofill helpers that depend on real framework
 * classes — android.net.Uri (extractRegistrableDomain) and org.json (parseSummariesJson)
 * — which are stubbed to throw in plain JVM unit tests. Both helpers are `internal`
 * instance methods on GabbroAutofillService, so we drive them through a Robolectric
 * service instance. Pure-data tests with no framework dependency live in the faster,
 * non-Robolectric GabbroAutofillServiceTest.
 */
@RunWith(RobolectricTestRunner::class)
class GabbroAutofillServiceRobolectricTest {

    private lateinit var service: GabbroAutofillService

    @Before
    fun setUp() {
        service = Robolectric.setupService(GabbroAutofillService::class.java)
    }

    // ── extractRegistrableDomain ──────────────────────────────────────────────

    @Test
    fun extractRegistrableDomain_null_blank_return_null() {
        assertNull(service.extractRegistrableDomain(null))
        assertNull(service.extractRegistrableDomain(""))
        assertNull(service.extractRegistrableDomain("   "))
    }

    @Test
    fun extractRegistrableDomain_strips_subdomain_scheme_and_path() {
        assertEquals("example.com", service.extractRegistrableDomain("https://www.example.com/login"))
    }

    @Test
    fun extractRegistrableDomain_adds_scheme_when_missing() {
        assertEquals("example.com", service.extractRegistrableDomain("example.com"))
    }

    @Test
    fun extractRegistrableDomain_collapses_arbitrary_subdomain() {
        assertEquals("example.com", service.extractRegistrableDomain("login.example.com"))
    }

    @Test
    fun extractRegistrableDomain_multipart_tld_keeps_registrable_label() {
        // Audit F-10 fixed: PSL-backed eTLD+1 keeps the real registrable label under
        // a multi-part public suffix instead of collapsing to the suffix itself.
        assertEquals("example.co.uk", service.extractRegistrableDomain("https://login.example.co.uk"))
    }

    @Test
    fun extractRegistrableDomain_unrelated_sites_under_shared_suffix_differ() {
        // The false-positive these fixes guard against: two unrelated real sites that
        // used to collapse to "co.uk" and cross-match. Now they stay distinct.
        assertEquals("bbc.co.uk", service.extractRegistrableDomain("https://bbc.co.uk"))
        assertEquals("hsbc.co.uk", service.extractRegistrableDomain("https://hsbc.co.uk"))
    }

    @Test
    fun extractRegistrableDomain_bare_public_suffix_is_null() {
        assertNull(service.extractRegistrableDomain("https://co.uk"))
    }

    @Test
    fun extractRegistrableDomain_rejects_ip_address() {
        assertNull(service.extractRegistrableDomain("https://192.168.1.1"))
    }

    @Test
    fun extractRegistrableDomain_trims_trailing_dot() {
        assertEquals("example.com", service.extractRegistrableDomain("https://example.com."))
    }

    @Test
    fun extractRegistrableDomain_lowercases_host() {
        assertEquals("example.com", service.extractRegistrableDomain("HTTPS://WWW.EXAMPLE.COM"))
    }

    @Test
    fun extractRegistrableDomain_ignores_port() {
        assertEquals("example.com", service.extractRegistrableDomain("https://example.com:8080"))
    }

    @Test
    fun extractRegistrableDomain_ignores_userinfo() {
        assertEquals("example.com", service.extractRegistrableDomain("https://user:pass@example.com"))
    }

    @Test
    fun extractRegistrableDomain_single_label_returned_as_is() {
        assertEquals("localhost", service.extractRegistrableDomain("localhost"))
    }

    // ── parseSummariesJson ────────────────────────────────────────────────────

    @Test
    fun parseSummariesJson_parses_array_with_empty_passwords() {
        val json = """
            [
              {"id":"1","username":"alice","url":"https://a.com"},
              {"id":"2","username":"bob","url":"https://b.com"}
            ]
        """.trimIndent()
        val result = service.parseSummariesJson(json)
        assertEquals(2, result.size)
        assertEquals(CredentialSummary("1", "alice", "https://a.com", ""), result[0])
        assertEquals(CredentialSummary("2", "bob", "https://b.com", ""), result[1])
        // password is never sourced from the summary feed — always blank here.
        assertTrue(result.all { it.password.isEmpty() })
    }

    @Test
    fun parseSummariesJson_empty_array_returns_empty_list() {
        assertTrue(service.parseSummariesJson("[]").isEmpty())
    }

    @Test
    fun parseSummariesJson_malformed_json_returns_empty_list() {
        assertTrue(service.parseSummariesJson("garbage not json").isEmpty())
    }

    @Test
    fun parseSummariesJson_one_missing_field_discards_whole_batch() {
        // DESIGN PROPERTY: the whole array is mapped inside a single try/catch, so a
        // single malformed entry (here: no "id") fails the entire parse rather than
        // skipping just the bad record. Pinned so any future change to partial-failure
        // handling is a deliberate, visible decision.
        val json = """[{"username":"alice","url":"https://a.com"},{"id":"2","username":"bob","url":"https://b.com"}]"""
        assertTrue(service.parseSummariesJson(json).isEmpty())
    }

    @Test
    fun parseSummariesJson_ignores_unknown_fields() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com","extra":"x","favourite":true}]"""
        val result = service.parseSummariesJson(json)
        assertEquals(1, result.size)
        assertEquals(CredentialSummary("1", "alice", "https://a.com", ""), result[0])
    }

    @Test
    fun parseSummariesJson_reads_app_id_field() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com","app_id":"com.company.app"}]"""
        val result = service.parseSummariesJson(json)
        assertEquals("com.company.app", result[0].appId)
    }

    @Test
    fun parseSummariesJson_missing_app_id_defaults_to_empty() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com"}]"""
        assertEquals("", service.parseSummariesJson(json)[0].appId)
    }

    // ── RecentAutofillApps (capture store) ────────────────────────────────────

    @Test
    fun recentAutofillApps_records_and_reads_back_most_recent_first() {
        val ctx = service.applicationContext
        RecentAutofillApps.record(ctx, "a.app")
        RecentAutofillApps.record(ctx, "b.app")
        assertEquals(listOf("b.app", "a.app"), RecentAutofillApps.recent(ctx))
    }

    @Test
    fun recentAutofillApps_caps_stored_entries() {
        val ctx = service.applicationContext
        for (i in 1..(RecentAutofillApps.CAP + 5)) {
            RecentAutofillApps.record(ctx, "app$i")
        }
        assertEquals(RecentAutofillApps.CAP, RecentAutofillApps.recent(ctx).size)
    }
}
