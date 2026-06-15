package app.gabbro.gabbro

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-JVM tests for the Public Suffix List matcher (no Android dependency).
 * A tiny inline rule set exercises normal, wildcard (*.), and exception (!) rules
 * plus the implicit "*" default. End-to-end coverage against the real vendored
 * list lives in GabbroAutofillServiceRobolectricTest (extractRegistrableDomain).
 */
class PublicSuffixListTest {

    // Minimal stand-in for the real list: normal rules, a wildcard, an exception.
    private val psl = PublicSuffixList.parse(
        listOf(
            "// a comment line is ignored",
            "com",
            "uk",
            "co.uk",
            "*.ck",
            "!www.ck",
            "",
        ),
    )

    @Test
    fun registrable_strips_subdomain() {
        assertEquals("example.com", psl.registrableDomain("login.example.com"))
    }

    @Test
    fun registrable_multipart_tld_keeps_one_label() {
        assertEquals("example.co.uk", psl.registrableDomain("login.example.co.uk"))
    }

    @Test
    fun registrable_unrelated_sites_under_shared_suffix_differ() {
        assertEquals("bbc.co.uk", psl.registrableDomain("bbc.co.uk"))
        assertEquals("hsbc.co.uk", psl.registrableDomain("hsbc.co.uk"))
    }

    @Test
    fun registrable_bare_public_suffix_is_null() {
        assertNull(psl.registrableDomain("co.uk"))
        assertNull(psl.registrableDomain("com"))
    }

    @Test
    fun registrable_wildcard_rule_consumes_one_label() {
        // *.ck makes foo.ck a public suffix, so www.foo.ck is the registrable domain.
        assertEquals("www.foo.ck", psl.registrableDomain("www.foo.ck"))
        assertNull(psl.registrableDomain("foo.ck"))
    }

    @Test
    fun registrable_exception_rule_overrides_wildcard() {
        // !www.ck exempts www.ck from *.ck, making ck the suffix and www.ck registrable.
        assertEquals("www.ck", psl.registrableDomain("www.ck"))
    }

    @Test
    fun registrable_unknown_tld_uses_default_rule() {
        assertEquals("example.faketld", psl.registrableDomain("shop.example.faketld"))
    }

    @Test
    fun registrable_blank_or_malformed_is_null() {
        assertNull(psl.registrableDomain(""))
        assertNull(psl.registrableDomain("   "))
        assertNull(psl.registrableDomain("example..com"))
    }

    @Test
    fun listed_suffix_recognises_real_rules_only() {
        assertTrue(psl.isListedSuffix("com"))
        assertFalse(psl.isListedSuffix("localhost"))
    }
}
