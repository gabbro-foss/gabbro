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
 * Robolectric-backed tests for the autofill matching helpers that depend on real
 * framework classes — android.net.Uri (extractRegistrableDomain) and org.json
 * (parseSummariesJson) — which are stubbed to throw in plain JVM unit tests. The
 * helpers are pure top-level functions; a Robolectric service instance is set up
 * only to load the real vendored PSL asset. Both autofill paths (the unlocked
 * GabbroAutofillService and the locked-vault UnlockActivity) route through the same
 * matchingCredentials function tested here. Pure-data tests with no framework
 * dependency live in the faster, non-Robolectric GabbroAutofillServiceTest.
 */
@RunWith(RobolectricTestRunner::class)
class GabbroAutofillServiceRobolectricTest {

    private lateinit var service: GabbroAutofillService
    private lateinit var psl: PublicSuffixList

    @Before
    fun setUp() {
        service = Robolectric.setupService(GabbroAutofillService::class.java)
        // Real vendored list — same one the service loads at runtime.
        psl = PublicSuffixList.fromAsset(service)
    }

    // Thin alias so the existing one-arg call sites read unchanged; the matcher is
    // now a pure top-level function taking the list explicitly.
    private fun registrable(input: String?): String? = extractRegistrableDomain(input, psl)

    // ── extractRegistrableDomain ──────────────────────────────────────────────

    @Test
    fun extractRegistrableDomain_null_blank_return_null() {
        assertNull(registrable(null))
        assertNull(registrable(""))
        assertNull(registrable("   "))
    }

    @Test
    fun extractRegistrableDomain_strips_subdomain_scheme_and_path() {
        assertEquals("example.com", registrable("https://www.example.com/login"))
    }

    @Test
    fun extractRegistrableDomain_adds_scheme_when_missing() {
        assertEquals("example.com", registrable("example.com"))
    }

    @Test
    fun extractRegistrableDomain_collapses_arbitrary_subdomain() {
        assertEquals("example.com", registrable("login.example.com"))
    }

    @Test
    fun extractRegistrableDomain_multipart_tld_keeps_registrable_label() {
        // Audit F-10 fixed: PSL-backed eTLD+1 keeps the real registrable label under
        // a multi-part public suffix instead of collapsing to the suffix itself.
        assertEquals("example.co.uk", registrable("https://login.example.co.uk"))
    }

    @Test
    fun extractRegistrableDomain_unrelated_sites_under_shared_suffix_differ() {
        // The false-positive these fixes guard against: two unrelated real sites that
        // used to collapse to "co.uk" and cross-match. Now they stay distinct.
        assertEquals("bbc.co.uk", registrable("https://bbc.co.uk"))
        assertEquals("hsbc.co.uk", registrable("https://hsbc.co.uk"))
    }

    @Test
    fun extractRegistrableDomain_bare_public_suffix_is_null() {
        assertNull(registrable("https://co.uk"))
    }

    @Test
    fun extractRegistrableDomain_rejects_ip_address() {
        assertNull(registrable("https://192.168.1.1"))
    }

    @Test
    fun extractRegistrableDomain_trims_trailing_dot() {
        assertEquals("example.com", registrable("https://example.com."))
    }

    @Test
    fun extractRegistrableDomain_lowercases_host() {
        assertEquals("example.com", registrable("HTTPS://WWW.EXAMPLE.COM"))
    }

    @Test
    fun extractRegistrableDomain_ignores_port() {
        assertEquals("example.com", registrable("https://example.com:8080"))
    }

    @Test
    fun extractRegistrableDomain_ignores_userinfo() {
        assertEquals("example.com", registrable("https://user:pass@example.com"))
    }

    @Test
    fun extractRegistrableDomain_single_label_returned_as_is() {
        assertEquals("localhost", registrable("localhost"))
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
        val result = parseSummariesJson(json)
        assertEquals(2, result.size)
        assertEquals(CredentialSummary("1", "alice", "https://a.com", ""), result[0])
        assertEquals(CredentialSummary("2", "bob", "https://b.com", ""), result[1])
        // password is never sourced from the summary feed — always blank here.
        assertTrue(result.all { it.password.isEmpty() })
    }

    @Test
    fun parseSummariesJson_empty_array_returns_empty_list() {
        assertTrue(parseSummariesJson("[]").isEmpty())
    }

    @Test
    fun parseSummariesJson_malformed_json_returns_empty_list() {
        assertTrue(parseSummariesJson("garbage not json").isEmpty())
    }

    @Test
    fun parseSummariesJson_one_missing_field_discards_whole_batch() {
        // DESIGN PROPERTY: the whole array is mapped inside a single try/catch, so a
        // single malformed entry (here: no "id") fails the entire parse rather than
        // skipping just the bad record. Pinned so any future change to partial-failure
        // handling is a deliberate, visible decision.
        val json = """[{"username":"alice","url":"https://a.com"},{"id":"2","username":"bob","url":"https://b.com"}]"""
        assertTrue(parseSummariesJson(json).isEmpty())
    }

    @Test
    fun parseSummariesJson_ignores_unknown_fields() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com","extra":"x","favourite":true}]"""
        val result = parseSummariesJson(json)
        assertEquals(1, result.size)
        assertEquals(CredentialSummary("1", "alice", "https://a.com", ""), result[0])
    }

    @Test
    fun parseSummariesJson_reads_app_id_field() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com","app_id":"com.company.app"}]"""
        val result = parseSummariesJson(json)
        assertEquals("com.company.app", result[0].appId)
    }

    @Test
    fun parseSummariesJson_missing_app_id_defaults_to_empty() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com"}]"""
        assertEquals("", parseSummariesJson(json)[0].appId)
    }

    @Test
    fun parseSummariesJson_reads_email_field() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com","email":"alice@example.com"}]"""
        assertEquals("alice@example.com", parseSummariesJson(json)[0].email)
    }

    @Test
    fun parseSummariesJson_missing_email_defaults_to_empty() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com"}]"""
        assertEquals("", parseSummariesJson(json)[0].email)
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

    // ── matchingCredentials ───────────────────────────────────────────────────
    // The single matcher shared by the unlocked path (GabbroAutofillService) and the
    // locked-vault path (UnlockActivity). Web context: PSL eTLD+1 equality. Native
    // context: exact app_id equality. Operates on password-free summaries — matching
    // never decrypts a secret.

    private fun cred(id: String, url: String, appId: String = "") =
        CredentialSummary(id = id, username = "user", url = url, password = "", appId = appId)

    // (1) web: an entry whose registrable domain equals the request's is offered.
    @Test
    fun matchingCredentials_web_exact_etld1_match() {
        val creds = listOf(cred("1", "https://example.com"))
        val matches = matchingCredentials(creds, "https://login.example.com", null, psl)
        assertEquals(1, matches.size)
        assertEquals("1", matches[0].id)
    }

    // (2) web F-10 guard: two unrelated sites under a shared multi-part suffix do not
    // cross-match. The old naive last-two-labels rule collapsed both to "co.uk".
    @Test
    fun matchingCredentials_web_unrelated_shared_suffix_no_cross_match() {
        val creds = listOf(cred("1", "https://hsbc.co.uk"))
        assertTrue(matchingCredentials(creds, "https://bbc.co.uk", null, psl).isEmpty())
    }

    // (3) web: a request whose domain cannot be extracted (bare suffix / IP) offers
    // nothing rather than matching loosely.
    @Test
    fun matchingCredentials_web_unextractable_request_no_match() {
        val creds = listOf(cred("1", "https://example.com"))
        assertTrue(matchingCredentials(creds, "https://co.uk", null, psl).isEmpty())
        assertTrue(matchingCredentials(creds, "https://192.168.1.1", null, psl).isEmpty())
    }

    // (4) native: exact package equality on the recorded app_id is offered.
    @Test
    fun matchingCredentials_native_exact_app_id_match() {
        val creds = listOf(cred("1", "https://example.com", appId = "com.company.app"))
        val matches = matchingCredentials(creds, null, "com.company.app", psl)
        assertEquals(1, matches.size)
        assertEquals("1", matches[0].id)
    }

    // (5) native regression: the old extractAppToken matched the package's token
    // ("paypal") as a substring of the entry URL. The hardened matcher uses app_id
    // only, so a URL substring is never a match.
    @Test
    fun matchingCredentials_native_no_substring_url_match() {
        val creds = listOf(cred("1", "https://paypal.com", appId = ""))
        assertTrue(
            matchingCredentials(creds, null, "com.paypal.android.p2pmobile", psl).isEmpty(),
        )
    }

    // (6) native: a blank app_id matches nothing even with a package present.
    @Test
    fun matchingCredentials_native_blank_app_id_no_match() {
        val creds = listOf(cred("1", "https://example.com", appId = ""))
        assertTrue(matchingCredentials(creds, null, "com.company.app", psl).isEmpty())
    }

    // (7) native: a different app_id does not match.
    @Test
    fun matchingCredentials_native_app_id_mismatch_no_match() {
        val creds = listOf(cred("1", "https://example.com", appId = "com.company.app"))
        assertTrue(matchingCredentials(creds, null, "com.other.app", psl).isEmpty())
    }

    // (8) match-before-decrypt invariant: parseSummariesJson never carries a password,
    // even if one is present in the feed — matching input is secret-free.
    @Test
    fun parseSummariesJson_passwords_always_blank() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com","password":"leak"}]"""
        assertEquals("", parseSummariesJson(json)[0].password)
    }

    // (9) match-before-decrypt invariant: matchingCredentials returns password-free
    // summaries — no decryption happens during matching.
    @Test
    fun matchingCredentials_returns_password_free_summaries() {
        val creds = listOf(cred("1", "https://example.com", appId = "com.company.app"))
        val matches = matchingCredentials(creds, null, "com.company.app", psl)
        assertTrue(matches.isNotEmpty())
        assertTrue(matches.all { it.password.isEmpty() })
    }
}
