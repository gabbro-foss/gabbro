package app.gabbro.gabbro

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import com.yubico.yubikit.android.YubiKitManager
import com.yubico.yubikit.android.transport.usb.UsbConfiguration
import com.yubico.yubikit.core.smartcard.SmartCardConnection
import com.yubico.yubikit.fido.client.ClientError
import com.yubico.yubikit.fido.client.Ctap2Client
import com.yubico.yubikit.fido.client.MultipleAssertionsAvailable
import com.yubico.yubikit.fido.client.PinRequiredClientError
import com.yubico.yubikit.fido.client.clientdata.ClientDataProvider
import com.yubico.yubikit.fido.client.extensions.HmacSecretExtension
import com.yubico.yubikit.fido.ctap.Ctap2Session
import com.yubico.yubikit.fido.webauthn.Extensions
import com.yubico.yubikit.fido.webauthn.PublicKeyCredentialCreationOptions
import com.yubico.yubikit.fido.webauthn.PublicKeyCredentialDescriptor
import com.yubico.yubikit.fido.webauthn.PublicKeyCredentialParameters
import com.yubico.yubikit.fido.webauthn.PublicKeyCredentialRequestOptions
import com.yubico.yubikit.fido.webauthn.PublicKeyCredentialRpEntity
import com.yubico.yubikit.fido.webauthn.PublicKeyCredentialUserEntity
import com.yubico.yubikit.fido.webauthn.SerializationType
import java.io.IOException
import java.security.SecureRandom

object YubiKeyManager {

    private const val RP_ID = "app.gabbro.gabbro"
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private var yubiKitManager: YubiKitManager? = null

    fun startUsbDiscovery(
        context: Context,
        onConnected: (SmartCardConnection) -> Unit,
        onError: (String) -> Unit,
    ) {
        val manager = YubiKitManager(context).also { yubiKitManager = it }
        manager.startUsbDiscovery(UsbConfiguration()) { device ->
            device.requestConnection(SmartCardConnection::class.java) { result ->
                try {
                    onConnected(result.getValue())
                } catch (e: IOException) {
                    mainHandler.post { onError("USB connection failed: ${e.message}") }
                }
            }
        }
    }

    fun stopUsbDiscovery() {
        yubiKitManager?.stopUsbDiscovery()
        yubiKitManager = null
    }

    fun register(
        connection: SmartCardConnection,
        pin: CharArray?,
        onSuccess: (credentialId: ByteArray) -> Unit,
        onError: (String) -> Unit,
    ) {
        try {
            val ctap2 = Ctap2Session(connection)
            val client = Ctap2Client(ctap2, listOf(HmacSecretExtension(true)))

            if (!client.isPinConfigured()) {
                mainHandler.post {
                    onError(
                        "YubiKey has no FIDO2 PIN. Set one in Yubico Authenticator or: ykman fido access change-pin"
                    )
                }
                return
            }

            val rp = PublicKeyCredentialRpEntity(RP_ID, "Gabbro")
            val userId = ByteArray(16).also { SecureRandom().nextBytes(it) }
            val user = PublicKeyCredentialUserEntity("gabbro-user", userId, "Gabbro User")
            val params = listOf(PublicKeyCredentialParameters("public-key", -7)) // ES256
            val challenge = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val creationExtensions = Extensions.fromMap(mapOf("hmacCreateSecret" to true))

            val options = PublicKeyCredentialCreationOptions(
                rp, user, challenge, params,
                null, null, null, null,
                creationExtensions
            )
            val clientDataHash = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val cdp = ClientDataProvider.fromHash(clientDataHash)

            val credential = client.makeCredential(cdp, options, RP_ID, pin, null, null)
            mainHandler.post { onSuccess(credential.getRawId()) }

        } catch (e: PinRequiredClientError) {
            mainHandler.post { onError("PIN required for registration: ${e.message}") }
        } catch (e: ClientError) {
            mainHandler.post { onError(describeClientError(e)) }
        } catch (e: Exception) {
            mainHandler.post { onError("Registration failed: ${e.message}") }
        }
    }

    fun getHmacSecret(
        connection: SmartCardConnection,
        credentialId: ByteArray,
        salt: ByteArray,
        pin: CharArray?,
        onSuccess: (ByteArray) -> Unit,
        onError: (String) -> Unit,
    ) {
        try {
            val ctap2 = Ctap2Session(connection)
            val client = Ctap2Client(ctap2, listOf(HmacSecretExtension(true)))

            val descriptor = PublicKeyCredentialDescriptor("public-key", credentialId)
            val saltB64 = Base64.encodeToString(salt, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            val requestExtensions = Extensions.fromMap(
                mapOf("hmacGetSecret" to mapOf("salt1" to saltB64))
            )
            val challenge = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val options = PublicKeyCredentialRequestOptions(
                challenge, null, RP_ID, listOf(descriptor), null, requestExtensions
            )
            val clientDataHash = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val cdp = ClientDataProvider.fromHash(clientDataHash)

            val assertion = client.getAssertion(cdp, options, RP_ID, pin, null)
            val extensionMap = assertion.getClientExtensionResults()?.toMap(SerializationType.CBOR) ?: emptyMap()

            val secret = extractHmacSecretOutput(extensionMap)
            if (secret != null) {
                mainHandler.post { onSuccess(secret) }
            } else {
                val topKeys = extensionMap.keys.joinToString()
                val innerKeys = (extensionMap["hmac-secret"] as? Map<*, *>)?.keys?.joinToString() ?: "n/a"
                mainHandler.post {
                    onError("hmac-secret output not found. Top-level keys: [$topKeys]; hmac-secret keys: [$innerKeys]")
                }
            }

        } catch (e: MultipleAssertionsAvailable) {
            mainHandler.post { onError("Multiple credentials matched — ambiguous credential ID: ${e.message}") }
        } catch (e: PinRequiredClientError) {
            mainHandler.post { onError("PIN required: ${e.message}") }
        } catch (e: ClientError) {
            mainHandler.post { onError(describeClientError(e)) }
        } catch (e: Exception) {
            mainHandler.post { onError("getHmacSecret failed: ${e.message}") }
        }
    }

    fun describeClientError(e: ClientError): String = when (e.errorCode) {
        ClientError.Code.DEVICE_INELIGIBLE ->
            "Device is not eligible — not a FIDO2 key, or credential not found"
        ClientError.Code.TIMEOUT ->
            "YubiKey timed out — tap the key when the light flashes"
        ClientError.Code.BAD_REQUEST ->
            "Bad request to YubiKey: ${e.message}"
        ClientError.Code.CONFIGURATION_UNSUPPORTED ->
            "YubiKey configuration not supported for this operation"
        else ->
            "YubiKey error (${e.errorCode}): ${e.message}"
    }

    private fun extractHmacSecretOutput(extensionMap: Map<String, Any>): ByteArray? {
        val hmacEntry = extensionMap["hmac-secret"] as? Map<*, *> ?: return null
        return hmacEntry["output1"] as? ByteArray
    }
}
