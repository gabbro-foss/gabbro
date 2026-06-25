package app.gabbro.gabbro

import android.service.autofill.Dataset
import android.service.autofill.FillResponse
import android.service.autofill.SaveInfo
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

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

    // ── Layer A: SaveInfo on the fill + auth FillResponses ─────────────────────
    // SaveInfo is the seam that makes onSaveRequest fire at all — without it the OS
    // never calls back. FillResponse/SaveInfo/Dataset have no compile-visible getters
    // (their accessors are @hide), so the assertions reflect on the real framework
    // classes Robolectric supplies. buildFillResponse/buildAuthResponse are internal
    // so these same-module tests can call them directly.

    // Mint a real AutofillId off a View under Robolectric (no public ctor exists).
    private fun newAutofillId(): AutofillId {
        val v = android.widget.EditText(service)
        v.id = android.view.View.generateViewId()
        return v.autofillId!!
    }

    private fun saveInfoOf(response: FillResponse): Any? =
        FillResponse::class.java.getMethod("getSaveInfo").invoke(response)

    private fun saveTypeOf(saveInfo: Any): Int =
        saveInfo.javaClass.getMethod("getType").invoke(saveInfo) as Int

    private fun idsVia(saveInfo: Any, getter: String): List<AutofillId> {
        val arr = saveInfo.javaClass.getMethod(getter).invoke(saveInfo) as Array<*>?
        return arr?.filterIsInstance<AutofillId>() ?: emptyList()
    }

    private fun datasetsOf(response: FillResponse): List<Dataset> {
        @Suppress("UNCHECKED_CAST")
        return (FillResponse::class.java.getMethod("getDatasets").invoke(response)
            as? List<Dataset>) ?: emptyList()
    }

    private fun fieldIdsOf(dataset: Dataset): List<AutofillId> {
        @Suppress("UNCHECKED_CAST")
        return (Dataset::class.java.getMethod("getFieldIds").invoke(dataset)
            as? List<AutofillId>) ?: emptyList()
    }

    private fun fieldValuesOf(dataset: Dataset): List<AutofillValue?> {
        @Suppress("UNCHECKED_CAST")
        return (Dataset::class.java.getMethod("getFieldValues").invoke(dataset)
            as? List<AutofillValue?>) ?: emptyList()
    }

    // The filled value placed on each field id — the contract that must survive the
    // setValue -> setField migration (the existing fieldIds-only assertions don't
    // prove a value was attached, only that the field was targeted).
    private fun valueByIdOf(dataset: Dataset): Map<AutofillId, AutofillValue?> =
        fieldIdsOf(dataset).zip(fieldValuesOf(dataset)).toMap()

    private fun text(s: String): AutofillValue = AutofillValue.forText(s)

    // The locked path attaches the unlock IntentSender at the Dataset level (the OS
    // renders it as one tappable chip), not on the FillResponse — so reflect the
    // Dataset's @hide getAuthentication().
    private fun datasetAuthOf(dataset: Dataset): Any? =
        Dataset::class.java.getMethod("getAuthentication").invoke(dataset)

    private val usernamePasswordType =
        SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD

    // A1 (pin): the unlocked fill path still puts a dataset on the matched fields.
    @Test
    fun buildFillResponse_fills_matched_username_and_password_datasets() {
        val uId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), listOf(pId), "https://example.com", null)
        val cred = CredentialSummary("1", "alice", "https://example.com", "secret")
        val datasets = datasetsOf(service.buildFillResponse(parsed, listOf(cred)))
        assertEquals(1, datasets.size)
        assertEquals(listOf(uId, pId), fieldIdsOf(datasets[0]))
    }

    // A2 (pin): the locked auth path still sets the unlock IntentSender + covers fields.
    @Test
    fun buildAuthResponse_sets_authentication_intent_and_covers_fields() {
        val uId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), listOf(pId), "https://example.com", null)
        val response = service.buildAuthResponse(parsed)
        val datasets = datasetsOf(response)
        assertEquals(1, datasets.size)
        assertNotNull(datasetAuthOf(datasets[0]))
        assertEquals(listOf(uId, pId), fieldIdsOf(datasets[0]))
    }

    // A3 (red): the fill response carries SaveInfo — password required, user/email optional.
    @Test
    fun buildFillResponse_carries_saveinfo_password_required_user_optional() {
        val uId = newAutofillId()
        val eId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(
            usernameIds = listOf(uId),
            passwordIds = listOf(pId),
            webDomain = "https://example.com",
            packageName = null,
            emailIds = listOf(eId),
        )
        val cred = CredentialSummary("1", "alice", "https://example.com", "secret")
        val saveInfo = saveInfoOf(service.buildFillResponse(parsed, listOf(cred)))
        assertNotNull("FillResponse must carry SaveInfo or the OS never calls onSaveRequest", saveInfo)
        assertEquals(usernamePasswordType, saveTypeOf(saveInfo!!))
        assertEquals(listOf(pId), idsVia(saveInfo, "getRequiredIds"))
        assertEquals(setOf(uId, eId), idsVia(saveInfo, "getOptionalIds").toSet())
    }

    // A4 (red): the auth (locked) response carries the same SaveInfo, so a changed
    // password saved on the locked -> unlock -> fill path still triggers a save.
    @Test
    fun buildAuthResponse_carries_saveinfo() {
        val uId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), listOf(pId), "https://example.com", null)
        val saveInfo = saveInfoOf(service.buildAuthResponse(parsed))
        assertNotNull(saveInfo)
        assertEquals(usernamePasswordType, saveTypeOf(saveInfo!!))
        assertEquals(listOf(pId), idsVia(saveInfo, "getRequiredIds"))
    }

    // A5 (guard): no password field means nothing worth saving — no SaveInfo attached
    // (also avoids SaveInfo.Builder rejecting an empty required-ids array).
    @Test
    fun buildFillResponse_without_password_field_has_no_saveinfo() {
        val uId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), emptyList(), "https://example.com", null)
        val cred = CredentialSummary("1", "alice", "https://example.com", "secret")
        assertNull(saveInfoOf(service.buildFillResponse(parsed, listOf(cred))))
    }

    // Unlocked + no match must still let the OS offer to SAVE a brand-new login:
    // a response carrying only SaveInfo (no datasets). Without a password field there
    // is nothing to save, so null.
    @Test
    fun buildSaveOnlyResponse_has_saveinfo_and_no_datasets_with_password() {
        val uId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), listOf(pId), "https://example.com", null)
        val response = service.buildSaveOnlyResponse(parsed)
        assertNotNull(response)
        assertNotNull(saveInfoOf(response!!))
        assertTrue(datasetsOf(response).isEmpty())
    }

    @Test
    fun buildSaveOnlyResponse_null_without_password_field() {
        val uId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), emptyList(), "https://example.com", null)
        assertNull(service.buildSaveOnlyResponse(parsed))
    }

    // ── Layer B: the filled VALUE on each field (the setValue -> setField contract) ──
    // The migration swaps the dataset-build mechanism; these pin that each field still
    // receives the right value. Run at the Robolectric default SDK (34, the setField
    // branch after migration); the legacy setValue branch is guarded by the sdk=33
    // variants below. Green against the current setValue code first (net-first).

    // B1: the unlocked fill path puts username -> username field, email -> email field,
    // password -> password field (with fillValueFor's username<->email fallback).
    @Test
    fun buildFillResponse_fills_correct_value_per_field_kind() {
        val uId = newAutofillId()
        val eId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(
            usernameIds = listOf(uId),
            passwordIds = listOf(pId),
            webDomain = "https://example.com",
            packageName = null,
            emailIds = listOf(eId),
        )
        val cred = CredentialSummary("1", "alice", "https://example.com", "secret", email = "alice@example.com")
        val byId = valueByIdOf(datasetsOf(service.buildFillResponse(parsed, listOf(cred)))[0])
        assertEquals(text("alice"), byId[uId])
        assertEquals(text("alice@example.com"), byId[eId])
        assertEquals(text("secret"), byId[pId])
    }

    // B2: the locked auth path puts a placeholder empty value on every field (the real
    // values arrive from UnlockActivity after unlock); A2 already pins ids + auth intent.
    @Test
    fun buildAuthResponse_sets_empty_placeholder_value_on_each_field() {
        val uId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), listOf(pId), "https://example.com", null)
        val byId = valueByIdOf(datasetsOf(service.buildAuthResponse(parsed))[0])
        assertEquals(text(""), byId[uId])
        assertEquals(text(""), byId[pId])
    }

    private fun presentation() =
        android.widget.RemoteViews(service.packageName, R.layout.autofill_unlock_item)

    // B3: the shared dataset builder used by BOTH fill paths (the unlocked service and
    // the locked-vault UnlockActivity, which had no prior coverage) fills correctly.
    private fun assertBuildFillDatasetFillsCorrectly() {
        val uId = newAutofillId()
        val eId = newAutofillId()
        val pId = newAutofillId()
        val cred = CredentialSummary("1", "alice", "https://example.com", "secret", email = "alice@example.com")
        val dataset = buildFillDataset(listOf(uId), listOf(eId), listOf(pId), cred, presentation())
        assertEquals(listOf(uId, eId, pId), fieldIdsOf(dataset))
        val byId = valueByIdOf(dataset)
        assertEquals(text("alice"), byId[uId])
        assertEquals(text("alice@example.com"), byId[eId])
        assertEquals(text("secret"), byId[pId])
    }

    // Default Robolectric SDK (34): the API 34+ setField branch.
    @Test
    fun buildFillDataset_fills_correct_value_per_field_kind() {
        assertBuildFillDatasetFillsCorrectly()
    }

    // Pre-34 device: the legacy setValue branch must fill identically (Android 8-13).
    @Test
    @Config(sdk = [33])
    fun buildFillDataset_fills_correct_value_on_legacy_device() {
        assertBuildFillDatasetFillsCorrectly()
    }

    // ── Layer C: fillField — the single gated primitive both branches share ─────
    // Directly pins that the value reaches the field on each side of the SDK gate, so
    // a future edit to the version check can never silently drop the value on one side.

    private fun assertFillFieldRoundTrips() {
        val id = newAutofillId()
        val builder = Dataset.Builder()
        builder.fillField(id, text("hunter2"), presentation())
        val dataset = builder.build()
        assertEquals(listOf(id), fieldIdsOf(dataset))
        assertEquals(text("hunter2"), valueByIdOf(dataset)[id])
    }

    @Test
    @Config(sdk = [34])
    fun fillField_sets_value_on_api34_setField_branch() {
        assertFillFieldRoundTrips()
    }

    @Test
    @Config(sdk = [33])
    fun fillField_sets_value_on_legacy_setValue_branch() {
        assertFillFieldRoundTrips()
    }

    // ── Layer C: matchSaveTarget (which existing login a save would update) ────
    // Reuses the strict fill matcher (PSL eTLD+1 / exact app_id) then narrows to the
    // captured identifier — so a save never targets an entry from another site/app
    // (zero false-positive), and a blank identifier never auto-targets anything.

    private fun loginCred(id: String, url: String, username: String, appId: String = "") =
        CredentialSummary(id = id, username = username, url = url, password = "", appId = appId)

    @Test
    fun matchSaveTarget_web_same_domain_and_identifier_returns_entry() {
        val captured = CapturedLogin("alice", "", "newpw")
        val summaries = listOf(loginCred("1", "https://example.com", "alice"))
        val match = matchSaveTarget(captured, summaries, "https://login.example.com", null, psl)
        assertEquals("1", match?.id)
    }

    @Test
    fun matchSaveTarget_web_identifier_match_is_case_insensitive() {
        val captured = CapturedLogin("Alice", "", "newpw")
        val summaries = listOf(loginCred("1", "https://example.com", "alice"))
        assertEquals("1", matchSaveTarget(captured, summaries, "https://example.com", null, psl)?.id)
    }

    @Test
    fun matchSaveTarget_web_same_site_different_identifier_returns_null() {
        val captured = CapturedLogin("bob", "", "newpw")
        val summaries = listOf(loginCred("1", "https://example.com", "alice"))
        assertNull(matchSaveTarget(captured, summaries, "https://example.com", null, psl))
    }

    @Test
    fun matchSaveTarget_native_app_id_and_identifier_returns_entry() {
        val captured = CapturedLogin("alice", "", "newpw")
        val summaries =
            listOf(loginCred("1", "https://example.com", "alice", appId = "com.company.app"))
        assertEquals("1", matchSaveTarget(captured, summaries, null, "com.company.app", psl)?.id)
    }

    @Test
    fun matchSaveTarget_different_site_returns_null() {
        val captured = CapturedLogin("alice", "", "newpw")
        val summaries = listOf(loginCred("1", "https://other.com", "alice"))
        assertNull(matchSaveTarget(captured, summaries, "https://example.com", null, psl))
    }

    @Test
    fun matchSaveTarget_multiple_same_site_returns_identifier_match() {
        val captured = CapturedLogin("bob", "", "newpw")
        val summaries = listOf(
            loginCred("1", "https://example.com", "alice"),
            loginCred("2", "https://example.com", "bob"),
        )
        assertEquals("2", matchSaveTarget(captured, summaries, "https://example.com", null, psl)?.id)
    }

    @Test
    fun matchSaveTarget_blank_identifier_never_auto_targets() {
        val captured = CapturedLogin("", "", "newpw")
        val summaries = listOf(loginCred("1", "https://example.com", ""))
        assertNull(matchSaveTarget(captured, summaries, "https://example.com", null, psl))
    }

    // ── F1: saveContextJson (the /autofill_save Kotlin -> Dart handoff) ────────
    // org.json is stubbed to throw in plain JVM tests, so these run under Robolectric.

    @Test
    fun saveContextJson_create_serializes_captured_and_candidates() {
        val captured = CapturedLogin("alice", "alice@example.com", "secret")
        val candidates = listOf(loginCred("1", "https://example.com", "alice"))
        val json = org.json.JSONObject(
            saveContextJson(captured, "example.com", "", SaveDecision.Create, candidates),
        )
        val cap = json.getJSONObject("captured")
        assertEquals("alice", cap.getString("username"))
        assertEquals("alice@example.com", cap.getString("email"))
        assertEquals("secret", cap.getString("password"))
        assertEquals("example.com", cap.getString("url"))
        assertEquals("", cap.getString("appId"))
        assertEquals("create", json.getJSONObject("decision").getString("action"))
        val cands = json.getJSONArray("candidates")
        assertEquals(1, cands.length())
        assertEquals("1", cands.getJSONObject(0).getString("id"))
        assertEquals("alice", cands.getJSONObject(0).getString("label"))
    }

    @Test
    fun saveContextJson_update_includes_matched_id() {
        val captured = CapturedLogin("alice", "", "secret")
        val dec = org.json.JSONObject(
            saveContextJson(captured, "example.com", "", SaveDecision.Update("id-9"), emptyList()),
        ).getJSONObject("decision")
        assertEquals("update", dec.getString("action"))
        assertEquals("id-9", dec.getString("matchedId"))
    }

    @Test
    fun saveContextJson_noop_action() {
        val captured = CapturedLogin("alice", "", "secret")
        val json = org.json.JSONObject(
            saveContextJson(captured, "example.com", "", SaveDecision.NoOp, emptyList()),
        )
        assertEquals("noop", json.getJSONObject("decision").getString("action"))
    }
}
