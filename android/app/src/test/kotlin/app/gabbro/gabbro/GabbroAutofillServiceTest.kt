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

    // ── classifyField ─────────────────────────────────────────────────────────
    // Pure per-field decision lifted out of the AssistStructure walk. android.*
    // constants used below are compile-time-inlined, so this runs in the fast
    // JVM lane with no Robolectric. The ViewNode glue that feeds these signals
    // is device-verified.

    // password-class inputType (TYPE_CLASS_TEXT | TYPE_TEXT_VARIATION_PASSWORD)
    private val passwordInputType =
        android.text.InputType.TYPE_CLASS_TEXT or
            android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD

    // email-class inputType (TYPE_CLASS_TEXT | TYPE_TEXT_VARIATION_EMAIL_ADDRESS)
    private val emailInputType =
        android.text.InputType.TYPE_CLASS_TEXT or
            android.text.InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS

    private fun classify(
        hints: List<String>? = null,
        inputType: Int = 0,
        htmlType: String? = null,
        htmlAutocomplete: String? = null,
        hint: String? = null,
        idEntry: String? = null,
        htmlName: String? = null,
    ): FieldKind = classifyField(
        autofillHints = hints,
        inputType = inputType,
        htmlType = htmlType,
        htmlAutocomplete = htmlAutocomplete,
        hint = hint,
        idEntry = idEntry,
        htmlName = htmlName,
    )

    // (1) autofill hint username — preserved
    @Test
    fun classifyField_autofill_hint_username_is_username() {
        assertEquals(FieldKind.USERNAME, classify(hints = listOf("username")))
    }

    // (2) autofill hint password — preserved
    @Test
    fun classifyField_autofill_hint_password_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(hints = listOf("password")))
    }

    // (3) the web miss: HTML type=password, no hints, inputType 0 -> Password
    @Test
    fun classifyField_html_type_password_with_no_other_signal_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(htmlType = "password", inputType = 0))
    }

    // (4) HTML type=email -> Username
    @Test
    fun classifyField_html_type_email_is_username() {
        assertEquals(FieldKind.USERNAME, classify(htmlType = "email"))
    }

    // (5) autocomplete current-/new-password -> Password
    @Test
    fun classifyField_autocomplete_current_and_new_password_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(htmlAutocomplete = "current-password"))
        assertEquals(FieldKind.PASSWORD, classify(htmlAutocomplete = "new-password"))
    }

    // (6) autocomplete username -> Username
    @Test
    fun classifyField_autocomplete_username_is_username() {
        assertEquals(FieldKind.USERNAME, classify(htmlAutocomplete = "username"))
    }

    // (7) inputType password variation — preserved
    @Test
    fun classifyField_inputtype_password_variation_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(inputType = passwordInputType))
    }

    // (8) inputType email variation — preserved
    @Test
    fun classifyField_inputtype_email_variation_is_username() {
        assertEquals(FieldKind.USERNAME, classify(inputType = emailInputType))
    }

    // (9) keyword password in name/id -> Password
    @Test
    fun classifyField_keyword_password_in_name_or_id_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(idEntry = "loginPassword"))
        assertEquals(FieldKind.PASSWORD, classify(htmlName = "user_password"))
    }

    // (10) keyword email/username/login/phone in hint/idEntry/name/id -> Username
    @Test
    fun classifyField_keyword_user_signals_are_username() {
        assertEquals(FieldKind.USERNAME, classify(hint = "Email or phone"))
        assertEquals(FieldKind.USERNAME, classify(idEntry = "user_login"))
        assertEquals(FieldKind.USERNAME, classify(htmlName = "username_field"))
        assertEquals(FieldKind.USERNAME, classify(hint = "Phone number"))
    }

    // (11) no signal at all -> None
    @Test
    fun classifyField_no_signal_is_none() {
        assertEquals(FieldKind.NONE, classify())
    }

    // (12) precedence: HTML type=password beats a stray "username" keyword
    @Test
    fun classifyField_html_password_beats_stray_username_keyword() {
        assertEquals(
            FieldKind.PASSWORD,
            classify(htmlType = "password", idEntry = "username_field"),
        )
    }
}
