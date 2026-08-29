package app.gabbro.gabbro

import android.content.Context
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/** The per-vault slot contract; a single shared slot once let one vault unlock another. */
@RunWith(RobolectricTestRunner::class)
class BiometricStoreTest {

    private lateinit var context: Context
    private val vaultA = "/vaults/a.gabbro"
    private val vaultB = "/vaults/b.gabbro"
    private val ct = byteArrayOf(1, 2, 3, 4)
    private val iv = byteArrayOf(9, 8, 7)

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("gabbro_biometric", Context.MODE_PRIVATE)
            .edit().clear().apply()
    }

    @Test
    fun store_two_vaults_both_enrolled() {
        BiometricStore.store(context, vaultA, ct, iv)
        BiometricStore.store(context, vaultB, ct, iv)
        assertTrue(BiometricStore.has(context, vaultA))
        assertTrue(BiometricStore.has(context, vaultB))
    }

    @Test
    fun forget_one_vault_leaves_the_other() {
        BiometricStore.store(context, vaultA, ct, iv)
        BiometricStore.store(context, vaultB, ct, iv)
        BiometricStore.forget(context, vaultA)
        assertFalse(BiometricStore.has(context, vaultA))
        assertTrue(BiometricStore.has(context, vaultB))
    }

    @Test
    fun key_alias_is_distinct_per_vault() {
        assertNotEquals(BiometricStore.keyAlias(vaultA), BiometricStore.keyAlias(vaultB))
    }

    @Test
    fun read_returns_stored_ciphertext_and_iv() {
        BiometricStore.store(context, vaultA, ct, iv)
        val got = BiometricStore.read(context, vaultA)
        assertArrayEquals(ct, got?.first)
        assertArrayEquals(iv, got?.second)
    }

    @Test
    fun read_returns_null_for_unenrolled_vault() {
        assertNull(BiometricStore.read(context, vaultA))
    }

    @Test
    fun has_false_for_different_vault_path() {
        BiometricStore.store(context, vaultA, ct, iv)
        assertFalse(BiometricStore.has(context, vaultB))
    }

    @Test
    fun suffix_is_stable_and_distinct_per_path() {
        assertTrue(BiometricStore.suffix(vaultA) == BiometricStore.suffix(vaultA))
        assertNotEquals(BiometricStore.suffix(vaultA), BiometricStore.suffix(vaultB))
    }
}
