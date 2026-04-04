package com.example.ai_personal_chief_mobile

import android.Manifest
import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "zyroai/native_telecom"
    private val requestRoleCode = 8411
    private var pendingRoleResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncCallAutomation" -> {
                        val prefs = getSharedPreferences("zyroai_native", Context.MODE_PRIVATE)
                        val dndMode = call.argument<Boolean>("dndMode") ?: false
                        val callAutoReply = call.argument<Boolean>("callAutoReply") ?: false
                        val smsAutoReply = call.argument<Boolean>("smsAutoReply") ?: false
                        val replyMessage = call.argument<String>("replyMessage")
                            ?: "The person is currently busy, drop your message for the user."
                        prefs.edit()
                            .putBoolean("dnd_mode", dndMode)
                            .putBoolean("call_auto_reply", callAutoReply)
                            .putBoolean("sms_auto_reply", smsAutoReply)
                            .putString("call_reply_message", replyMessage)
                            .apply()
                        result.success(true)
                    }

                    "getCallScreeningStatus" -> {
                        val prefs = getSharedPreferences("zyroai_native", Context.MODE_PRIVATE)
                        val roleManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            getSystemService(RoleManager::class.java)
                        } else {
                            null
                        }
                        result.success(
                            mapOf(
                                "supported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N),
                                "roleHeld" to (roleManager?.isRoleHeld(RoleManager.ROLE_CALL_SCREENING) == true),
                                "dndMode" to prefs.getBoolean("dnd_mode", false),
                                "callAutoReply" to prefs.getBoolean("call_auto_reply", false),
                                "smsAutoReply" to prefs.getBoolean("sms_auto_reply", false),
                                "smsPermissionGranted" to hasSmsPermission(),
                                "replyMessage" to prefs.getString(
                                    "call_reply_message",
                                    "The person is currently busy, drop your message for the user."
                                )
                            )
                        )
                    }

                    "sendSms" -> {
                        val phoneNumber = call.argument<String>("phoneNumber")?.trim().orEmpty()
                        val message = call.argument<String>("message")?.trim().orEmpty()
                        if (phoneNumber.isBlank() || message.isBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(sendSms(phoneNumber, message))
                    }

                    "requestCallScreeningRole" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val roleManager = getSystemService(RoleManager::class.java)
                        if (roleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        pendingRoleResult = result
                        startActivityForResult(
                            roleManager.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING),
                            requestRoleCode
                        )
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun hasSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun sendSms(phoneNumber: String, message: String): Boolean {
        if (!hasSmsPermission()) return false
        return try {
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java) ?: SmsManager.getDefault()
            } else {
                SmsManager.getDefault()
            }
            smsManager.sendTextMessage(phoneNumber, null, message, null, null)
            true
        } catch (_: Exception) {
            false
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == requestRoleCode) {
            pendingRoleResult?.success(resultCode == Activity.RESULT_OK)
            pendingRoleResult = null
        }
    }
}
