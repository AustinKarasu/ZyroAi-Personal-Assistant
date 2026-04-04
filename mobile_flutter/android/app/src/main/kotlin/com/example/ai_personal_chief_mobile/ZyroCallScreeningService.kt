package com.example.ai_personal_chief_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService
import android.telephony.SmsManager
import androidx.core.content.ContextCompat

class ZyroCallScreeningService : CallScreeningService() {
    override fun onScreenCall(callDetails: Call.Details) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return
        }

        val prefs = getSharedPreferences("zyroai_native", Context.MODE_PRIVATE)
        val dndMode = prefs.getBoolean("dnd_mode", false)
        val callAutoReply = prefs.getBoolean("call_auto_reply", false)
        val smsAutoReply = prefs.getBoolean("sms_auto_reply", false)
        val replyMessage = prefs.getString(
            "call_reply_message",
            "The person is currently busy, drop your message for the user."
        ) ?: "The person is currently busy, drop your message for the user."
        val isIncoming = callDetails.callDirection == Call.Details.DIRECTION_INCOMING

        val response = if (isIncoming && dndMode && callAutoReply) {
            if (smsAutoReply) {
                sendBusyReply(callDetails, replyMessage)
            }
            CallResponse.Builder()
                .setDisallowCall(true)
                .setRejectCall(true)
                .setSkipCallLog(false)
                .setSkipNotification(false)
                .build()
        } else {
            CallResponse.Builder()
                .setDisallowCall(false)
                .setRejectCall(false)
                .setSkipCallLog(false)
                .setSkipNotification(false)
                .build()
        }

        respondToCall(callDetails, response)
    }

    @Suppress("DEPRECATION")
    private fun sendBusyReply(callDetails: Call.Details, replyMessage: String) {
        val number = callDetails.handle?.schemeSpecificPart?.trim().orEmpty()
        if (number.isBlank()) return
        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.SEND_SMS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        try {
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java) ?: SmsManager.getDefault()
            } else {
                SmsManager.getDefault()
            }
            smsManager.sendTextMessage(number, null, replyMessage, null, null)
        } catch (_: Exception) {
            // Ignore failures so call screening never crashes on messaging errors.
        }
    }
}
