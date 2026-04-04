package com.example.ai_personal_chief_mobile

import android.Manifest
import android.app.Activity
import android.app.DownloadManager
import android.app.role.RoleManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.telephony.SmsManager
import androidx.core.content.ContextCompat
import androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "zyroai/native_telecom"
    private val requestRoleCode = 8411
    private val requestInstallPackagesCode = 8412
    private var pendingRoleResult: MethodChannel.Result? = null
    private var pendingInstallPath: String? = null
    private var pendingInstallMimeType: String = "application/vnd.android.package-archive"
    private var downloadReceiverRegistered = false

    private val downloadReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
            val prefs = getSharedPreferences("zyroai_native", Context.MODE_PRIVATE)
            val expectedId = prefs.getLong("update_download_id", -1L)
            val completedId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
            if (expectedId == -1L || completedId != expectedId) return

            val path = prefs.getString("update_apk_path", null) ?: return
            prefs.edit().remove("update_download_id").apply()
            installDownloadedApk(path)
        }
    }

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

                    "downloadAndInstallApk" -> {
                        val url = call.argument<String>("url")?.trim().orEmpty()
                        val version = call.argument<String>("version")?.trim().orEmpty()
                        if (url.isBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(downloadAndInstallApk(url, version))
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

    override fun onStart() {
        super.onStart()
        if (downloadReceiverRegistered) return
        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.registerReceiver(this, downloadReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(downloadReceiver, filter)
        }
        downloadReceiverRegistered = true
    }

    override fun onStop() {
        if (downloadReceiverRegistered) {
            runCatching { unregisterReceiver(downloadReceiver) }
            downloadReceiverRegistered = false
        }
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        pendingInstallPath?.let { path ->
            if (canInstallPackages()) {
                installDownloadedApk(path)
            }
        }
    }

    private fun hasSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun canInstallPackages(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
    }

    private fun downloadAndInstallApk(url: String, version: String): Boolean {
        return try {
            val fileName = if (version.isBlank()) "zyroai-update.apk" else "ZyroAi-$version.apk"
            val targetFile = File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), fileName)
            if (targetFile.exists()) {
                targetFile.delete()
            }

            val request = DownloadManager.Request(Uri.parse(url))
                .setTitle("ZyroAi update")
                .setDescription("Downloading the latest ZyroAi release")
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(false)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setMimeType("application/vnd.android.package-archive")
                .setDestinationUri(Uri.fromFile(targetFile))

            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val downloadId = manager.enqueue(request)
            getSharedPreferences("zyroai_native", Context.MODE_PRIVATE)
                .edit()
                .putLong("update_download_id", downloadId)
                .putString("update_apk_path", targetFile.absolutePath)
                .apply()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun installDownloadedApk(path: String) {
        val file = File(path)
        if (!file.exists()) return

        pendingInstallPath = path
        if (!canInstallPackages()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                        data = Uri.parse("package:$packageName")
                    },
                    requestInstallPackagesCode
                )
            }
            return
        }

        val apkUri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, pendingInstallMimeType)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(installIntent)
        pendingInstallPath = null
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
            return
        }
        if (requestCode == requestInstallPackagesCode && resultCode == Activity.RESULT_OK) {
            pendingInstallPath?.let { installDownloadedApk(it) }
        }
    }
}
