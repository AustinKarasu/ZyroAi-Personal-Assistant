package com.example.ai_personal_chief_mobile

import android.content.Context
import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService

class ZyroCallScreeningService : CallScreeningService() {
    override fun onScreenCall(callDetails: Call.Details) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return
        }

        val prefs = getSharedPreferences("zyroai_native", Context.MODE_PRIVATE)
        val dndMode = prefs.getBoolean("dnd_mode", false)
        val callAutoReply = prefs.getBoolean("call_auto_reply", false)
        val isIncoming = callDetails.callDirection == Call.Details.DIRECTION_INCOMING

        val response = if (isIncoming && dndMode && callAutoReply) {
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
}
