package app.gabbro.gabbro

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "app.gabbro.gabbro/yubikey"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val pin = call.argument<String>("pin")?.toCharArray()
                when (call.method) {
                    "register_and_get_hmac" -> {
                        val saltHex = call.argument<String>("salt")
                        if (saltHex == null) {
                            result.error("BAD_ARGS", "salt required", null)
                            return@setMethodCallHandler
                        }
                        YubiKeyManager.startUsbDiscovery(
                            this,
                            onConnected = { connection ->
                                YubiKeyManager.registerAndGetHmac(
                                    connection, saltHex.fromHex(), pin,
                                    onSuccess = { credId, hmacSecret ->
                                        YubiKeyManager.stopUsbDiscovery()
                                        result.success(mapOf(
                                            "credentialId" to credId.toHex(),
                                            "hmacSecret" to hmacSecret.toHex(),
                                        ))
                                    },
                                    onError = { msg ->
                                        YubiKeyManager.stopUsbDiscovery()
                                        result.error("REGISTER_HMAC_FAILED", msg, null)
                                    },
                                )
                            },
                            onError = { msg ->
                                result.error("USB_ERROR", msg, null)
                            },
                        )
                    }
                    "register" -> {
                        YubiKeyManager.startUsbDiscovery(
                            this,
                            onConnected = { connection ->
                                YubiKeyManager.register(
                                    connection, pin,
                                    onSuccess = { credId ->
                                        YubiKeyManager.stopUsbDiscovery()
                                        result.success(credId.toHex())
                                    },
                                    onError = { msg ->
                                        YubiKeyManager.stopUsbDiscovery()
                                        result.error("REGISTER_FAILED", msg, null)
                                    },
                                )
                            },
                            onError = { msg ->
                                result.error("USB_ERROR", msg, null)
                            },
                        )
                    }
                    "get_hmac_secret" -> {
                        val credIdHex = call.argument<String>("credentialId")
                        if (credIdHex == null) {
                            result.error("BAD_ARGS", "credentialId required", null)
                            return@setMethodCallHandler
                        }
                        val saltHex = call.argument<String>("salt")
                        if (saltHex == null) {
                            result.error("BAD_ARGS", "salt required", null)
                            return@setMethodCallHandler
                        }
                        YubiKeyManager.startUsbDiscovery(
                            this,
                            onConnected = { connection ->
                                YubiKeyManager.getHmacSecret(
                                    connection, credIdHex.fromHex(), saltHex.fromHex(), pin,
                                    onSuccess = { secret ->
                                        YubiKeyManager.stopUsbDiscovery()
                                        result.success(secret.toHex())
                                    },
                                    onError = { msg ->
                                        YubiKeyManager.stopUsbDiscovery()
                                        result.error("HMAC_FAILED", msg, null)
                                    },
                                )
                            },
                            onError = { msg ->
                                result.error("USB_ERROR", msg, null)
                            },
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    private fun String.fromHex(): ByteArray {
        check(length % 2 == 0) { "Hex string must have even length" }
        return ByteArray(length / 2) { i -> substring(i * 2, i * 2 + 2).toInt(16).toByte() }
    }
}
