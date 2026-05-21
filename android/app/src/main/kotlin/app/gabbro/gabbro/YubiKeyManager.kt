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
            mainHandler.post { onError("NFC is disabled — enable it in Settings") }
            return
        }
        val manager = YubiKitManager(activity).also { nfcManager = it }
        manager.startNfcDiscovery(NfcConfiguration(), activity) { device ->
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

    fun registerAndGetHmac(
        connection: YubiKeyConnection,
        salt: ByteArray,
        pin: CharArray?,
        onSuccess: (credentialId: ByteArray, hmacSecret: ByteArray) -> Unit,
        onError: (String) -> Unit,
    ) {
        try {
            val session = ctap2Session(connection)
            val info = session.cachedInfo
            val pinProtocol = pinProtocolFor(info)
            val clientPin = ClientPin(session, pinProtocol)

            val nonNullPin = pin ?: run { mainHandler.post { onError("PIN required") }; return }

            // Single PIN token covering both MC and GA — avoids a second getPinToken
            // call (which can itself prompt a touch on CTAP2.1 firmware 5.4+).
            val pinToken = clientPin.getPinToken(
                nonNullPin,
                ClientPin.PIN_PERMISSION_MC or ClientPin.PIN_PERMISSION_GA,
                RP_ID,
            )

            // 1. makeCredential — one tap here
            val mcClientDataHash = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val pinUvAuthParamMC = pinProtocol.authenticate(pinToken, mcClientDataHash)
            val userId = ByteArray(16).also { SecureRandom().nextBytes(it) }
            val credential = session.makeCredential(
                mcClientDataHash,
                mapOf("id" to RP_ID, "name" to "Gabbro"),
                mapOf("id" to userId, "name" to "gabbro-user", "displayName" to "Gabbro User"),
                listOf(mapOf("type" to "public-key", "alg" to -7)),
                null,
                mapOf("hmac-secret" to true),
                null,
                pinUvAuthParamMC,
                pinProtocol.version,
                null,
                null,
            )
            val authDataMC = AuthenticatorData.parseFrom(ByteBuffer.wrap(credential.authenticatorData))
            val credentialId = authDataMC.attestedCredentialData?.credentialId
                ?: error("No attested credential data in makeCredential response")

            // 2. getAssertions for hmac-secret — reuse same token, up=false, no second tap
            val keyAgreementResult = clientPin.getSharedSecret()
            val platformKey = keyAgreementResult.first
            val sharedSecret = keyAgreementResult.second
            val encryptedSalt = pinProtocol.encrypt(sharedSecret, salt)
            val saltAuth = pinProtocol.authenticate(sharedSecret, encryptedSalt)

            val gaClientDataHash = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val pinUvAuthParamGA = pinProtocol.authenticate(pinToken, gaClientDataHash)

            val allowList = listOf(mapOf("type" to "public-key", "id" to credentialId))
            val extensions = mapOf(
                "hmac-secret" to mapOf(1 to platformKey, 2 to encryptedSalt, 3 to saltAuth)
            )
            val assertions = session.getAssertions(
                RP_ID, gaClientDataHash, allowList, extensions, mapOf("up" to false),
                pinUvAuthParamGA, pinProtocol.version, null,
            )
            if (assertions.isEmpty()) {
                mainHandler.post { onError("No credential matched after registration") }
                return
            }
            val authDataGA = AuthenticatorData.parseFrom(
                ByteBuffer.wrap(assertions.first().authenticatorData)
            )
            val encryptedOutput = authDataGA.extensions?.get("hmac-secret") as? ByteArray
                ?: run {
                    mainHandler.post { onError("hmac-secret missing from getAssertions response") }
                    return
                }
            val hmacSecret = pinProtocol.decrypt(sharedSecret, encryptedOutput)
            mainHandler.post { onSuccess(credentialId, hmacSecret) }

        } catch (e: Exception) {
            mainHandler.post { onError("registerAndGetHmac failed: ${e.message}") }
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

    private fun ctap2Session(connection: YubiKeyConnection): Ctap2Session = when (connection) {
        is SmartCardConnection -> Ctap2Session(connection)
        is FidoConnection -> Ctap2Session(connection)
        else -> throw IllegalArgumentException("Unsupported connection: ${connection::class.simpleName}")
    }

    private fun pinProtocolFor(info: Ctap2Session.InfoData) =
        if (2 in info.pinUvAuthProtocols) PinUvAuthProtocolV2() else PinUvAuthProtocolV1()
}
