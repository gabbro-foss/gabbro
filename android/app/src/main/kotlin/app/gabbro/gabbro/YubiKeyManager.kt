package app.gabbro.gabbro

import android.app.Activity
import android.content.Context
import android.nfc.NfcAdapter
import android.os.Handler
import android.os.Looper
import com.yubico.yubikit.android.YubiKitManager
import com.yubico.yubikit.android.transport.nfc.NfcConfiguration
import com.yubico.yubikit.android.transport.usb.UsbConfiguration
import com.yubico.yubikit.android.transport.usb.connection.UsbFidoConnection
import com.yubico.yubikit.core.YubiKeyConnection
import com.yubico.yubikit.core.fido.FidoConnection
import com.yubico.yubikit.core.smartcard.SmartCardConnection
import com.yubico.yubikit.fido.ctap.ClientPin
import com.yubico.yubikit.fido.ctap.Ctap2Session
import com.yubico.yubikit.fido.ctap.PinUvAuthProtocolV1
import com.yubico.yubikit.fido.ctap.PinUvAuthProtocolV2
import com.yubico.yubikit.fido.webauthn.AuthenticatorData
import java.io.IOException
import java.nio.ByteBuffer
import java.security.SecureRandom

object YubiKeyManager {

    private const val RP_ID = "app.gabbro.gabbro"
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private var usbManager: YubiKitManager? = null
    private var nfcManager: YubiKitManager? = null

    fun startUsbDiscovery(
        context: Context,
        onConnected: (YubiKeyConnection) -> Unit,
        onError: (String) -> Unit,
    ) {
        val manager = YubiKitManager(context).also { usbManager = it }
        manager.startUsbDiscovery(UsbConfiguration()) { device ->
            device.requestConnection(UsbFidoConnection::class.java) { result ->
                try {
                    onConnected(result.getValue())
                } catch (e: IOException) {
                    mainHandler.post { onError("USB connection failed: ${e.message}") }
                }
            }
        }
    }

    fun stopUsbDiscovery() {
        usbManager?.stopUsbDiscovery()
        usbManager = null
    }

    fun startNfcDiscovery(
        activity: Activity,
        onConnected: (YubiKeyConnection) -> Unit,
        onError: (String) -> Unit,
    ) {
        val adapter = NfcAdapter.getDefaultAdapter(activity)
        if (adapter == null) {
            mainHandler.post { onError("NFC not available on this device") }
            return
        }
        if (!adapter.isEnabled) {
            mainHandler.post { onError("NFC is disabled. Move your YubiKey away from the phone, then enable NFC in Settings.") }
            return
        }
        val manager = YubiKitManager(activity).also { nfcManager = it }
        manager.startNfcDiscovery(NfcConfiguration().skipNdefCheck(true), activity) { device ->
            device.requestConnection(SmartCardConnection::class.java) { result ->
                try {
                    onConnected(result.getValue())
                } catch (e: IOException) {
                    mainHandler.post { onError("NFC connection failed: ${e.message}") }
                }
            }
        }
    }

    fun stopNfcDiscovery(activity: Activity) {
        nfcManager?.stopNfcDiscovery(activity)
        nfcManager = null
    }

    fun register(
        connection: YubiKeyConnection,
        pin: CharArray?,
        onSuccess: (credentialId: ByteArray) -> Unit,
        onError: (String) -> Unit,
    ) {
        try {
            val session = ctap2Session(connection)
            val info = session.cachedInfo
            val pinProtocol = pinProtocolFor(info)
            val clientPin = ClientPin(session, pinProtocol)

            val nonNullPin = pin ?: run { mainHandler.post { onError("PIN required") }; return }
            val clientDataHash = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val pinToken = clientPin.getPinToken(nonNullPin, ClientPin.PIN_PERMISSION_MC, RP_ID)
            val pinUvAuthParam = pinProtocol.authenticate(pinToken, clientDataHash)

            val userId = ByteArray(16).also { SecureRandom().nextBytes(it) }
            val credential = session.makeCredential(
                clientDataHash,
                mapOf("id" to RP_ID, "name" to "Gabbro"),
                mapOf("id" to userId, "name" to "gabbro-user", "displayName" to "Gabbro User"),
                listOf(mapOf("type" to "public-key", "alg" to -7)),
                null,
                mapOf("hmac-secret" to true),
                null,
                pinUvAuthParam,
                pinProtocol.version,
                null,
                null,
            )

            val authData = AuthenticatorData.parseFrom(ByteBuffer.wrap(credential.authenticatorData))
            val credentialId = authData.attestedCredentialData?.credentialId
                ?: error("No attested credential data in makeCredential response")
            mainHandler.post { onSuccess(credentialId) }

        } catch (e: Exception) {
            mainHandler.post { onError("Registration failed: ${e.message}") }
        }
    }

    fun getHmacSecret(
        connection: YubiKeyConnection,
        credentialId: ByteArray,
        salt: ByteArray,
        pin: CharArray?,
        onSuccess: (ByteArray) -> Unit,
        onError: (String) -> Unit,
    ) {
        try {
            val session = ctap2Session(connection)
            val info = session.cachedInfo
            val pinProtocol = pinProtocolFor(info)
            val clientPin = ClientPin(session, pinProtocol)

            // Separate key agreement for hmac-secret salt encryption (not the PIN UV key agreement)
            val keyAgreementResult = clientPin.getSharedSecret()
            val platformKey = keyAgreementResult.first
            val sharedSecret = keyAgreementResult.second
            val encryptedSalt = pinProtocol.encrypt(sharedSecret, salt)
            val saltAuth = pinProtocol.authenticate(sharedSecret, encryptedSalt)

            val nonNullPin = pin ?: run { mainHandler.post { onError("PIN required") }; return }
            val clientDataHash = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val pinToken = clientPin.getPinToken(nonNullPin, ClientPin.PIN_PERMISSION_GA, RP_ID)
            val pinUvAuthParam = pinProtocol.authenticate(pinToken, clientDataHash)

            val allowList = listOf(mapOf("type" to "public-key", "id" to credentialId))
            val extensions = mapOf(
                "hmac-secret" to mapOf(1 to platformKey, 2 to encryptedSalt, 3 to saltAuth)
            )

            val assertions = session.getAssertions(
                RP_ID, clientDataHash, allowList, extensions, null,
                pinUvAuthParam, pinProtocol.version, null,
            )

            if (assertions.isEmpty()) {
                mainHandler.post { onError("No credential matched on this key") }
                return
            }

            val authData = AuthenticatorData.parseFrom(
                ByteBuffer.wrap(assertions.first().authenticatorData)
            )
            val encryptedOutput = authData.extensions?.get("hmac-secret") as? ByteArray
                ?: run {
                    val keys = authData.extensions?.keys?.joinToString() ?: "none"
                    mainHandler.post {
                        onError("hmac-secret missing from assertion extensions. Keys present: [$keys]")
                    }
                    return
                }

            val secret = pinProtocol.decrypt(sharedSecret, encryptedOutput)
            mainHandler.post { onSuccess(secret) }

        } catch (e: Exception) {
            mainHandler.post { onError("getHmacSecret failed: ${e.message}") }
        }
    }

    /**
     * Multi-credential hmac-secret assertion — one tap regardless of which registered key is
     * inserted.
     *
     * For 2+ records, all C(n,2) credential pairs are tried sequentially using a 64-byte combined
     * salt (salt_i ∥ salt_j). The authenticator returns NO_CREDENTIALS immediately (no tap) for
     * non-matching pairs and taps once for the matching pair. The correct 32-byte half is
     * extracted based on which credential matched.
     *
     * Mirrors [get_hmac_secret_any_of] in rust/src/fido/device.rs.
     */
    fun getHmacSecretAny(
        connection: YubiKeyConnection,
        records: List<Pair<ByteArray, ByteArray>>,
        pin: CharArray?,
        onSuccess: (hmac: ByteArray, credentialId: ByteArray) -> Unit,
        onError: (String) -> Unit,
    ) {
        if (records.isEmpty()) {
            mainHandler.post { onError("No records provided") }
            return
        }

        try {
            val session = ctap2Session(connection)
            val info = session.cachedInfo
            val pinProtocol = pinProtocolFor(info)
            val clientPin = ClientPin(session, pinProtocol)

            val nonNullPin = pin ?: run { mainHandler.post { onError("PIN required") }; return }
            val pinToken = clientPin.getPinToken(nonNullPin, ClientPin.PIN_PERMISSION_GA, RP_ID)

            // One key-agreement for the whole session.
            val keyAgreementResult = clientPin.getSharedSecret()
            val platformKey = keyAgreementResult.first
            val sharedSecret = keyAgreementResult.second

            if (records.size == 1) {
                // Single-credential path: 32-byte salt, mirrors getHmacSecret.
                val (credId, salt) = records[0]
                val encryptedSalt = pinProtocol.encrypt(sharedSecret, salt)
                val saltAuth = pinProtocol.authenticate(sharedSecret, encryptedSalt)
                val clientDataHash = ByteArray(32).also { SecureRandom().nextBytes(it) }
                val pinUvAuthParam = pinProtocol.authenticate(pinToken, clientDataHash)
                val allowList = listOf(mapOf("type" to "public-key", "id" to credId))
                val extensions = mapOf("hmac-secret" to mapOf(1 to platformKey, 2 to encryptedSalt, 3 to saltAuth))
                val assertions = session.getAssertions(RP_ID, clientDataHash, allowList, extensions, null, pinUvAuthParam, pinProtocol.version, null)
                if (assertions.isEmpty()) { mainHandler.post { onError("No credential matched") }; return }
                val authData = AuthenticatorData.parseFrom(ByteBuffer.wrap(assertions.first().authenticatorData))
                val encryptedOutput = authData.extensions?.get("hmac-secret") as? ByteArray
                    ?: run { mainHandler.post { onError("hmac-secret missing from assertion") }; return }
                mainHandler.post { onSuccess(pinProtocol.decrypt(sharedSecret, encryptedOutput), credId) }
                return
            }

            // 2+ records: try all C(n,2) pairs. Non-matching pairs throw CtapException
            // (NO_CREDENTIALS) before user interaction — loop continues without a tap.
            for (i in records.indices) {
                for (j in (i + 1) until records.size) {
                    try {
                        val (cred0, salt0) = records[i]
                        val (cred1, salt1) = records[j]

                        val combinedSalt = ByteArray(64)
                        System.arraycopy(salt0, 0, combinedSalt, 0, 32)
                        System.arraycopy(salt1, 0, combinedSalt, 32, 32)

                        val encryptedSalt = pinProtocol.encrypt(sharedSecret, combinedSalt)
                        val saltAuth = pinProtocol.authenticate(sharedSecret, encryptedSalt)

                        val clientDataHash = ByteArray(32).also { SecureRandom().nextBytes(it) }
                        val pinUvAuthParam = pinProtocol.authenticate(pinToken, clientDataHash)

                        val allowList = listOf(
                            mapOf("type" to "public-key", "id" to cred0),
                            mapOf("type" to "public-key", "id" to cred1),
                        )
                        val extensions = mapOf(
                            "hmac-secret" to mapOf(1 to platformKey, 2 to encryptedSalt, 3 to saltAuth)
                        )

                        val assertions = session.getAssertions(
                            RP_ID, clientDataHash, allowList, extensions, null,
                            pinUvAuthParam, pinProtocol.version, null,
                        )

                        if (assertions.isEmpty()) continue

                        val firstAssertion = assertions.first()
                        val matchedCredId = firstAssertion.credential?.get("id") as? ByteArray
                            ?: run { mainHandler.post { onError("No credential ID in assertion response") }; return }

                        val authData = AuthenticatorData.parseFrom(
                            ByteBuffer.wrap(firstAssertion.authenticatorData)
                        )
                        val encryptedOutput = authData.extensions?.get("hmac-secret") as? ByteArray
                            ?: run { mainHandler.post { onError("hmac-secret missing from assertion") }; return }

                        val decryptedOutput = pinProtocol.decrypt(sharedSecret, encryptedOutput)
                        if (decryptedOutput.size < 64) {
                            mainHandler.post { onError("hmac-secret output too short: ${decryptedOutput.size}") }
                            return
                        }

                        val hmac = when {
                            matchedCredId.contentEquals(cred0) -> decryptedOutput.copyOfRange(0, 32)
                            matchedCredId.contentEquals(cred1) -> decryptedOutput.copyOfRange(32, 64)
                            else -> {
                                mainHandler.post { onError("Assertion credential ID does not match either record in pair ($i, $j)") }
                                return
                            }
                        }

                        mainHandler.post { onSuccess(hmac, matchedCredId) }
                        return

                    } catch (_: Exception) {
                        continue  // NO_CREDENTIALS or transient failure — try next pair
                    }
                }
            }

            mainHandler.post { onError("No matching FIDO2 credential found among registered records") }

        } catch (e: Exception) {
            mainHandler.post { onError("getHmacSecretAny failed: ${e.message}") }
        }
    }

    private fun ctap2Session(connection: YubiKeyConnection): Ctap2Session = when (connection) {
        is SmartCardConnection -> Ctap2Session(connection)
        is FidoConnection -> Ctap2Session(connection)
        else -> throw IllegalArgumentException("Unsupported connection: ${connection::class.simpleName}")
    }

    private fun pinProtocolFor(info: Ctap2Session.InfoData) =
        if (2 in info.pinUvAuthProtocols) PinUvAuthProtocolV2() else PinUvAuthProtocolV1()
}
