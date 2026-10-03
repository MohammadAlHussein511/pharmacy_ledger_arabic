package com.pharmacy.ledger

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * FlutterFragmentActivity is required by local_auth (BiometricPrompt).
 *
 * The "biometric guard" key lives in the Android Keystore with
 * setInvalidatedByBiometricEnrollment(true). Android permanently invalidates
 * it when fingerprints are added/removed or the screen lock is removed, which
 * lets the app detect enrollment changes and fall back to the PIN safely.
 * No biometric data is ever read or stored by the app.
 */
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.pharmacy.ledger/biometric_key"
    private val keyAlias = "pharmacy_ledger_biometric_guard"
    private val transformation =
        "${KeyProperties.KEY_ALGORITHM_AES}/${KeyProperties.BLOCK_MODE_CBC}/${KeyProperties.ENCRYPTION_PADDING_PKCS7}"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "createKey" -> {
                            createKey()
                            result.success(true)
                        }
                        "keyStatus" -> result.success(keyStatus())
                        "deleteKey" -> {
                            deleteKey()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("KEY_ERROR", e.message, null)
                }
            }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun createKey() {
        deleteKey()
        val spec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_CBC)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_PKCS7)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .build()
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(spec)
        generator.generateKey()
    }

    private fun keyStatus(): String {
        return try {
            val key = keyStore().getKey(keyAlias, null) as? SecretKey ?: return "missing"
            Cipher.getInstance(transformation).init(Cipher.ENCRYPT_MODE, key)
            "valid"
        } catch (e: KeyPermanentlyInvalidatedException) {
            "invalidated"
        } catch (e: android.security.keystore.UserNotAuthenticatedException) {
            // Key exists and is intact; it simply needs authentication to be used.
            "valid"
        } catch (e: Exception) {
            "error"
        }
    }

    private fun deleteKey() {
        val ks = keyStore()
        if (ks.containsAlias(keyAlias)) ks.deleteEntry(keyAlias)
    }
}
