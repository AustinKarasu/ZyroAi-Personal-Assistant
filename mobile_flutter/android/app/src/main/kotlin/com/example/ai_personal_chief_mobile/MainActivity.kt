package com.example.ai_personal_chief_mobile

import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
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
                        val replyMessage = call.argument<String>("replyMessage")
                            ?: "The person is currently busy, drop your message for the user."
                        prefs.edit()
                            .putBoolean("dnd_mode", dndMode)
                            .putBoolean("call_auto_reply", callAutoReply)
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
                                "replyMessage" to prefs.getString(
                                    "call_reply_message",
                                    "The person is currently busy, drop your message for the user."
                                )
                            )
                        )
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

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == requestRoleCode) {
            pendingRoleResult?.success(resultCode == Activity.RESULT_OK)
            pendingRoleResult = null
        }
    }
}
